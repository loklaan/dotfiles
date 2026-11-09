# MCP Authentication

MCPProxy ingress uses machine-local `api_key` in `~/.mcpproxy/mcp_config.json`
(0600; directory 0700). It is separate from upstream credentials and quarantine.
`require_mcp_auth=true` remains mandatory on loopback: Linux `nginxProxy` can
forward traffic off-host without adding authentication. Readiness is not proof of auth.

## Key lifecycle

Full apply order:
1. `run_before_install-056-generate-mcpproxy-api-key.sh.tmpl` uses `jq` to seed a
   missing key: 32 random bytes → 64 lowercase hex characters. Existing keys and
   unrelated config survive unchanged.
2. Clients read `mcpproxy-api-key-tmpl`; `modify_private_mcp_config.json` preserves
   the key while overlaying managed settings.
3. Startup is gated by `mcpproxyGate`: Linux runs the Pitchfork-managed
   `df-mcpproxy` daemon, macOS uses MCPProxy.app.

MCPProxy can generate a key at startup, but that happens after client rendering.
Keep seeding **before targets** to avoid requiring two applies. Applies never rotate keys.

| Exception | Outcome |
|---|---|
| Missing `jq` | Seed warns, leaves config unchanged; an existing key remains usable |
| Failed config/key read | Seed warns without overwriting; later template parsing may still abort apply |
| Missing file/key | OpenCode/Codex omit credentials; Claude renders a diagnostic comment; auth stays required |
| Explicit-target apply | Skips numbered scripts, including seeding; cannot bootstrap a missing key |

## Client delivery and ownership

| Client | Credential location |
|---|---|
| Claude Code/Desktop | `mcp-remote@latest --header-file ~/.mcpproxy/mcp-client-headers` |
| Codex | `~/.codex/config.toml`: `http_headers.Authorization` |
| OpenCode V1 | `mcp.mcpproxy.headers.Authorization` |
| OpenCode V2 | `mcp.servers.mcpproxy.headers.Authorization`, from the same `mcp-client-tmpl` projection |

- Real keys never enter argv: Claude passes a file path; others read config.
  Proxy/header/Codex files have `private_` attributes. OpenCode relies on its
  private `.config` ancestor, **not** an explicit 0600 file attribute.
- `home/.chezmoitemplates/mcp-client-tmpl` owns every client projection from the
  same lane, including auth. `home/private_dot_config/opencode2/modify_opencode.json`
  consumes it directly, so V1/V2 headers cannot drift.
- `home/dot_codex/modify_private_config.toml` is a private marked-section
  modifier: it keeps Codex-owned settings outside the managed block while the
  block carries `http_headers.Authorization`. It creates config, not the Codex
  executable.
- The proxy modifier overlays owned server definitions while retaining matching
  entries' OAuth/quarantine state. It does not approve tools. Upstream `env`,
  `headers` and OAuth authenticate proxy → server, not client → proxy.

## Check authentication

These POST probes invoke no upstream tools. Use the effective endpoint if it
differs from the default below:

```bash
initialize='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"auth-check","version":"1.0"}}}'
mcp_probe() {
  curl --max-time 10 -sS -o /dev/null -w '%{http_code}\n' \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    "$@" --data "$initialize" 'http://127.0.0.1:18321/mcp/'
}

mcp_probe                                                        # expect 401
mcp_probe -H 'Authorization: Bearer deliberately-wrong-key'       # expect 401
mcp_probe --header "@${HOME}/.mcpproxy/mcp-client-headers"          # expect 200
```

- The wrong key is synthetic. Keep real keys in the private file; never use
  inline values, command substitution or authenticated `curl -v`/`--trace`.
- `000`/connection failure is not an auth result. Correct-key 401: check stale
  client headers or different proxy config; re-render and reconnect clients.
- For isolated `initialize`, `tools/list` and REST checks:
  `bash tests/security-integrations/mcp-auth.test.sh`. See [Tests](../../tests/README.md).

## Rotation

Run the headless rotation task when you want a fresh key:

```bash
mise run mcp:rotate-key
```

### When to rotate

Use `--check` as the signal:

```bash
df-mcpproxy-rotate-key --check
```

It reports the key's age (default max 90 days, override with
`DF_MCPPROXY_KEY_MAX_AGE_DAYS`) and scans for exposure: wrong config/header/dir
modes, the current key in session logs or shell history, and the current key in
process argv. Exit status is 0 when healthy and 1 when rotation is due.

`--if-due` is the automation entry point: it rotates only when `--check` is due,
and exits immediately otherwise. `df-task-update` (the normal `mise run update`
path) calls it after every apply. Any scheduler can call the same command:

```bash
df-mcpproxy-rotate-key --if-due
```

Calendar rotation is optional; the stronger triggers are exposure, a device or
account lifecycle change, and an interrupted rotation. The exposure scan makes
those event triggers visible without polling you.

`df-mcpproxy-rotate-key` owns the whole operation:

1. Acquires `~/.local/state/dotfiles/mcpproxy/rotate.lock` so concurrent rotations
   cannot overlap.
2. Generates a key into a private temp file, writes it into `mcp_config.json`
   atomically with mode 0600, and records only its SHA-256 in a phase receipt.
3. Re-renders every client with `chezmoi apply --force --exclude=scripts`, so no
   package install or daemon lifecycle script runs as a side effect.
4. Restarts the running proxy (`pitchfork restart df-mcpproxy` on Linux;
   quit/reopen MCPProxy.app on macOS).
5. Verifies the live boundary: **401** without the header file and **200** with it.

The receipt makes the operation resumable. If a phase is interrupted, re-running
the same command continues from `key-written` or `clients-rendered` without
rotating again, as long as the config still holds the receipt's key hash.
`--force` ignores a resumable receipt and rotates a fresh key.

The command never prints the key, never passes it in argv, and does not open
session logging. Clients pick up the new key when the apply renders them; already
running client sessions may need a reconnect after the proxy restart. If the
proxy is not running, rotation still completes and the next launch uses the new
key.

## Related credentials and logs

[Secrets Architecture](../rules/secrets-architecture.md) owns logging/xtrace and
private atomic-write invariants. OpenCode's auth modifier is
`home/private_dot_local/share/opencode/modify_private_auth.json`; it updates both
account-key entries while preserving unrelated providers and existing
credentials when BWS returns empty.
