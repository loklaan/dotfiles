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
3. `run_after_install-056-mcpproxy-daemon.sh.tmpl` handles startup through
   Pitchfork (Linux) or MCPProxy.app (macOS), gated by `mcpproxyGate`.

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
| OpenCode V2 | `mcp.servers.mcpproxy.headers.Authorization`, translated from V1's shared partial |

- Real keys never enter argv: Claude passes a file path; others read config.
  Proxy/header/Codex files have `private_` attributes. OpenCode relies on its
  private `.config` ancestor, **not** an explicit 0600 file attribute.
- `home/.chezmoitemplates/mcp-servers-{claude-json,codex-toml,opencode-mcpproxy-json}-tmpl`
  own client definitions; `home/private_dot_config/opencode2/modify_opencode.json`
  must preserve headers during translation.
- `home/dot_codex/modify_private_config.toml` replaces/moves its
  `# --- BEGIN CHEZMOI MANAGED SECTION ---` / `# --- END CHEZMOI MANAGED SECTION ---`
  block to the top, preserving surrounding settings with whitespace normalisation.
  It creates config, not the Codex executable. Unmarked duplicate
  `[mcp_servers.mcpproxy]` sections require manual reconciliation.
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

Deliberate maintenance, separate from probes and upstream credential rotation:
1. Coordinate with clients; stop `df-mcpproxy` via `pitchfork stop df-mcpproxy`
   on Linux, or quit MCPProxy.app on macOS. Keep host recovery access.
2. In a trusted local editor, remove **only `api_key`**. Retain server/OAuth/
   quarantine state; never delete the config or copy it into the repository.
3. Full `chezmoi apply` with `jq` reseeds and re-renders clients; startup follows
   `mcpproxyGate`. Start manually through the usual manager only if intended.
4. Restart/reconnect clients and repeat the probes. Never paste keys into commands,
   reports or tickets.

## Related credentials and logs

[Secrets Architecture](../rules/secrets-architecture.md) owns logging/xtrace and
private atomic-write invariants. OpenCode's seed is
`home/private_dot_local/share/opencode/private_auth.json.tmpl`; Linux
`run_after_install-065-opencode-auth.sh.tmpl` updates both account-key entries,
preserving unrelated providers and existing credentials when BWS returns empty.
