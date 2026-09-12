#!/usr/bin/env bash
# shellcheck disable=SC2016

#|----------------------------------------------------------------------------|
#| MCPProxy ingress authentication regression tests                           |
#|                                                                            |
#| Run: bash tests/security-integrations/mcp-auth.test.sh                      |
#|                                                                            |
#| The harness renders templates and starts one isolated, upstream-free       |
#| MCPProxy on a random loopback port. It never reads or calls the live proxy. |
#|----------------------------------------------------------------------------|

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(mktemp -d)"
PASS=0
FAIL=0
SERVER_PID=""
SCRATCH_KEY="mcpproxy-security-regression-key"

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }

cleanup() {
  local root="$ROOT"
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
  rm -rf "$root"
  printf '  cleanup  stopped scratch MCPProxy and removed %s\n' "$root"
}
trap cleanup EXIT INT TERM

render_inline() {
  local home="$1" template="$2" output="$3"
  chezmoi execute-template -S "$REPO/home" \
    --override-data "{\"chezmoi\":{\"homeDir\":\"$home\"}}" \
    "{{ includeTemplate \"$template\" . }}" > "$output"
}

render_v2() {
  local home="$1" output="$2"
  local data
  data="$(jq -cn --arg home "$home" '{
    chezmoi: {homeDir: $home, stdin: "{}"},
    machineProfile: "personal",
    profiles: {personal: {snapshot: true, provider_block: {}, enabled_providers: []}},
    bwsTokenPath: ($home + "/missing-bws-token")
  }')"
  chezmoi execute-template -S "$REPO/home" --override-data "$data" \
    --file "$REPO/home/private_dot_config/opencode2/modify_opencode.json" > "$output"
}

render_proxy_config() {
  local stdin_json="$1" output="$2"
  local data
  data="$(jq -cn --arg stdin "$stdin_json" --arg home "$ROOT/render-home" '{
    chezmoi: {homeDir: $home, stdin: $stdin},
    machineProfile: "personal",
    ports: {mcpproxy: {internal: 18321}},
    bwsTokenPath: ($home + "/missing-bws-token")
  }')"
  chezmoi execute-template -S "$REPO/home" --override-data "$data" \
    --file "$REPO/home/private_dot_mcpproxy/modify_private_mcp_config.json" > "$output"
}

http_post() {
  local url="$1" body="$2" output="$3"
  shift 3
  curl -sS -o "$output" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    "$@" --data "$body" "$url"
}

printf '\nfirst-run rendering fails closed\n'
FIRST_HOME="$ROOT/first-home"
mkdir -p "$FIRST_HOME"
render_inline "$FIRST_HOME" mcp-servers-opencode-mcpproxy-json-tmpl "$ROOT/first-opencode.json"
render_inline "$FIRST_HOME" mcp-servers-claude-json-tmpl "$ROOT/first-claude.json"
check "OpenCode omits an unavailable credential" "$(jq -r '.mcpproxy | has("headers")' "$ROOT/first-opencode.json")" false
check "Claude config contains no inline credential" "$(jq -r '.mcpproxy | has("env")' "$ROOT/first-claude.json")" false
render_proxy_config '{}' "$ROOT/first-proxy.json"
check "server authentication remains required without a key" "$(jq -r '.require_mcp_auth' "$ROOT/first-proxy.json")" true
check "first-run migration does not invent or rotate api_key" "$(jq -r 'has("api_key")' "$ROOT/first-proxy.json")" false

printf '\nexisting installation reuses one credential across clients\n'
EXISTING_HOME="$ROOT/existing-home"
mkdir -p "$EXISTING_HOME/.mcpproxy"
jq -n --arg key "$SCRATCH_KEY" '{api_key: $key, unrelated: "preserved"}' > "$EXISTING_HOME/.mcpproxy/mcp_config.json"
chmod 600 "$EXISTING_HOME/.mcpproxy/mcp_config.json"
render_inline "$EXISTING_HOME" mcp-servers-opencode-mcpproxy-json-tmpl "$ROOT/opencode.json"
render_inline "$EXISTING_HOME" mcp-servers-claude-json-tmpl "$ROOT/claude.json"
chezmoi execute-template -S "$REPO/home" \
  --override-data "{\"chezmoi\":{\"homeDir\":\"$EXISTING_HOME\"}}" \
  --file "$REPO/home/private_dot_mcpproxy/private_mcp-client-headers.tmpl" > "$ROOT/mcp-client-headers"
render_v2 "$EXISTING_HOME" "$ROOT/opencode2.json"
check "OpenCode V1 sends the bearer header" "$(jq -r '.mcpproxy.headers.Authorization' "$ROOT/opencode.json")" "Bearer $SCRATCH_KEY"
check "OpenCode V2 preserves the bearer header" "$(jq -r '.mcp.servers.mcpproxy.headers.Authorization' "$ROOT/opencode2.json")" "Bearer $SCRATCH_KEY"
check "Claude reads the private header file" "$(jq -r '.mcpproxy.args | join(" ")' "$ROOT/claude.json")" "-y mcp-remote@latest http://127.0.0.1:18321/mcp/ --header-file $EXISTING_HOME/.mcpproxy/mcp-client-headers"
if jq -r '.mcpproxy.args[]' "$ROOT/claude.json" | grep -qF "$SCRATCH_KEY"; then
  no "Claude process argv excludes the credential"
else
  ok "Claude process argv excludes the credential"
fi
check "Claude's private header file carries the bearer" "$(<"$ROOT/mcp-client-headers")" "Authorization: Bearer $SCRATCH_KEY"
EXISTING_INPUT="$(jq -cn --arg key "$SCRATCH_KEY" '{
  api_key: $key,
  unrelated: "preserved",
  mcpServers: [{name: "context7", quarantined: true}]
}')"
render_proxy_config "$EXISTING_INPUT" "$ROOT/existing-proxy.json"
check "server config preserves its existing api_key" "$(jq -r '.api_key' "$ROOT/existing-proxy.json")" "$SCRATCH_KEY"
check "server config preserves unrelated state" "$(jq -r '.unrelated' "$ROOT/existing-proxy.json")" preserved
check "server config preserves loopback binding" "$(jq -r '.listen' "$ROOT/existing-proxy.json")" '127.0.0.1:18321'
check "server config preserves quarantine state" "$(jq -r '.mcpServers[] | select(.name == "context7") | .quarantined' "$ROOT/existing-proxy.json")" true

printf '\nreal protocol boundary\n'
PORT="$(node -e 'const n=require("node:net");const s=n.createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})')"
DATA_DIR="$ROOT/mcpproxy-data"
CONFIG="$ROOT/mcp_config.json"
mkdir -p "$DATA_DIR"
jq -n --arg key "$SCRATCH_KEY" --arg listen "127.0.0.1:$PORT" --arg data "$DATA_DIR" '{
  listen: $listen,
  data_dir: $data,
  api_key: $key,
  require_mcp_auth: true,
  mcpServers: [],
  telemetry: {enabled: false}
}' > "$CONFIG"
mcpproxy serve --config "$CONFIG" --data-dir "$DATA_DIR" --listen "127.0.0.1:$PORT" > "$ROOT/server.log" 2>&1 &
SERVER_PID=$!
READY=""
for _ in {1..100}; do
  READY="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/ready" 2>/dev/null || true)"
  [[ "$READY" == 200 ]] && break
  sleep 0.05
done
check "scratch MCPProxy becomes ready" "$READY" 200

INITIALIZE='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"security-regression","version":"1.0.0"}}}'
TOOLS_LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
MCP_URL="http://127.0.0.1:$PORT/mcp"
NO_AUTH="$(http_post "$MCP_URL" "$INITIALIZE" "$ROOT/no-auth.body")"
WRONG_AUTH="$(http_post "$MCP_URL" "$INITIALIZE" "$ROOT/wrong-auth.body" -H 'Authorization: Bearer wrong-key')"
CORRECT_AUTH="$(curl -sS -D "$ROOT/init.headers" -o "$ROOT/init.body" -w '%{http_code}' \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H "Authorization: Bearer $SCRATCH_KEY" --data "$INITIALIZE" "$MCP_URL")"
check "initialize without authorization is rejected" "$NO_AUTH" 401
check "initialize with an invalid bearer is rejected" "$WRONG_AUTH" 401
check "initialize with the correct bearer succeeds" "$CORRECT_AUTH" 200
if grep -q '"jsonrpc":"2.0"' "$ROOT/init.body" && grep -q '"result"' "$ROOT/init.body"; then
  ok "initialize returns a JSON-RPC result"
else
  no "initialize returns a JSON-RPC result"
fi

SESSION_ID=""
while IFS= read -r line; do
  line="${line%$'\r'}"
  case "$line" in
    [Mm][Cc][Pp]-[Ss]ession-[Ii][Dd]:*) SESSION_ID="${line#*: }" ;;
  esac
done < "$ROOT/init.headers"
TOOLS_ARGS=(-H "Authorization: Bearer $SCRATCH_KEY")
[[ -n "$SESSION_ID" ]] && TOOLS_ARGS+=(-H "Mcp-Session-Id: $SESSION_ID")
TOOLS_NONE="$(http_post "$MCP_URL" "$TOOLS_LIST" "$ROOT/tools-none.body")"
TOOLS_WRONG="$(http_post "$MCP_URL" "$TOOLS_LIST" "$ROOT/tools-wrong.body" -H 'Authorization: Bearer wrong-key')"
TOOLS_AUTH="$(http_post "$MCP_URL" "$TOOLS_LIST" "$ROOT/tools.body" "${TOOLS_ARGS[@]}")"
check "tools/list without authorization is rejected" "$TOOLS_NONE" 401
check "tools/list with an invalid bearer is rejected" "$TOOLS_WRONG" 401
check "tools/list with the correct bearer succeeds" "$TOOLS_AUTH" 200
if grep -q '"tools"' "$ROOT/tools.body"; then
  ok "tools/list returns a protocol result"
else
  no "tools/list returns a protocol result"
fi

REST_URL="http://127.0.0.1:$PORT/api/v1/status"
REST_NONE="$(curl -sS -o "$ROOT/rest-none.body" -w '%{http_code}' "$REST_URL")"
REST_WRONG="$(curl -sS -o "$ROOT/rest-wrong.body" -w '%{http_code}' -H 'Authorization: Bearer wrong-key' "$REST_URL")"
REST_VALID="$(curl -sS -o "$ROOT/rest-valid.body" -w '%{http_code}' -H "Authorization: Bearer $SCRATCH_KEY" "$REST_URL")"
check "REST status without authorization is rejected" "$REST_NONE" 401
check "REST status with an invalid bearer is rejected" "$REST_WRONG" 401
check "REST status with the correct bearer succeeds" "$REST_VALID" 200
printf '  HTTP status receipt: initialize=%s/%s/%s tools-list=%s/%s/%s REST=%s/%s/%s\n' \
  "$NO_AUTH" "$WRONG_AUTH" "$CORRECT_AUTH" \
  "$TOOLS_NONE" "$TOOLS_WRONG" "$TOOLS_AUTH" \
  "$REST_NONE" "$REST_WRONG" "$REST_VALID"
if grep -qF "$SCRATCH_KEY" "$ROOT/server.log"; then
  no "scratch credential is absent from server logs"
else
  ok "scratch credential is absent from server logs"
fi

cleanup
trap - EXIT INT TERM
printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
