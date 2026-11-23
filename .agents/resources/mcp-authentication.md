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
  same lane, including auth. `home/private_dot_config/opencode/modify_private_opencode.json`
  consumes it directly, so V1/V2 headers cannot drift.
- `home/dot_codex/modify_private_config.toml` is a private marked-section
  modifier: it keeps Codex-owned settings outside the managed block while the
  block carries `http_headers.Authorization`. It creates config, not the Codex
  executable.
- The proxy modifier overlays owned server definitions while retaining matching
  entries' OAuth/quarantine state. It does not approve tools. Upstream `env`,
  `headers` and OAuth authenticate proxy → server, not client → proxy.

## Upstream OAuth

A server with its own provider OAuth (notion today) authenticates provider →
MCPProxy, not client → proxy. The API key above never reaches the provider;
MCPProxy holds the grant. Two per-server OAuth keys look similar, and only one
is public:

| Key | Meaning |
|---|---|
| `oauth.redirect_uri` | Loopback only (`http`, loopback host, explicit port). MCPProxy derives it; never set it from dotfiles. |
| `oauth.callback_base_url` | Absolute **https origin** for the provider's browser redirect. This is the public knob. |

A catalogue entry opts in by carrying an `oauth` block. `mcp-catalogue-tmpl`
fills `callback_base_url` from machine-local
`[data.mcpproxy] oauthCallbackBaseUrl` and leaves `client_id` empty so DCR
registers the proxy; entries without the block never gain one. The value is
validated once per render — `https`, no credentials, path, query, fragment or
trailing slash, optional port 1-65535 — so a bad origin fails the render
instead of the proxy at start.

`oauth.client_id` is never generated. A non-empty id skips DCR, and the provider
then rejects the unregistered id at its authorization endpoint (`invalid_client`,
never a redirect), so only an id an entry already carries is preserved. Dropping
an entry's `oauth` block withdraws `callback_base_url` from the deployed entry,
so the public origin is unregistered rather than left behind.

Setting the DCR `client_name` would need an upstream mcpproxy change: 0.73.0
hardcodes `mcpproxy-go` and drops an `oauth.client_name` key from config, so
dotfiles do not attempt it. Notion keys a custom client on its redirect URL,
which is why `oauth.callback_base_url` is what distinguishes machines.

MCPProxy registers `https://<base>/oauth/callback/<server-name>` and serves it on
its main listener. A machine-local nginx server block that chezmoi does not
manage publishes exactly that prefix on the dedicated ingress port and returns
404 for everything else. Only `/oauth/callback/` is published — `/oauth/authorize`
and `/oauth/token` are not — which is why that prefix, not the host, is the
whole trust boundary. The block is written by hand because it is
machine-specific ingress, so nothing in this repo renders or removes it:

```nginx
map $http_x_forwarded_proto $fwd_proto {
    default $http_x_forwarded_proto;
    ""      $scheme;
}

limit_req_zone $binary_remote_addr zone=oauth_callback:1m rate=10r/s;

server {
    listen 9184 default_server;
    listen [::]:9184 default_server;
    server_name _;
    server_tokens off;
    client_max_body_size 8k;

    location /oauth/callback/ {
        limit_except GET { deny all; }   # only if the provider redirect is GET
        limit_req zone=oauth_callback burst=20 nodelay;
        proxy_pass http://127.0.0.1:18321;   # no URI part: path forwarded verbatim
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $fwd_proto;
        proxy_set_header X-Forwarded-Host $host;
        proxy_read_timeout 120s;
    }

    location / { return 404; }
}
```

The provider's browser redirect cannot carry a bearer key, so the path is
deliberately outside the api_key boundary. Do not widen it, and do not reuse the
control-panel port: that one proxies the whole admin UI.

The flow is protected by a single-use `state` value plus PKCE, so publishing the
callback URL does not by itself let anyone redeem a code. `proxy_read_timeout`
bounds a single proxied request at 120 seconds; it is not the consent deadline.
Consent happens at the provider, and MCPProxy's own pending-flow window is 120
seconds — that window, not nginx, is the binding limit. A consent that outlasts
it has to be restarted.

On exe.dev, switch the one public share port to the dedicated ingress port and
make it public; keep the admin UI port private. Only one port can be public, so
the admin UI and the callback cannot share it.

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
