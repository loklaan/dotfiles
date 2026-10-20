#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# MCP catalogue -> local additions -> per-client projection contract.
# Renders templates with temporary data and destination; never runs apply.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
H="${ROOT}/home"
MCPPROXY="${H}/private_dot_mcpproxy/modify_private_mcp_config.json"
OC1="${H}/private_dot_config/opencode/modify_opencode.json"
OC2="${H}/private_dot_config/opencode2/modify_opencode.json"
CLAUDE="${H}/modify_dot_claude.json"
DESKTOP="${H}/Library/Application Support/Claude/modify_claude_desktop_config.json"
CODEX="${H}/dot_codex/modify_config.toml"
SLIM="${H}/private_dot_config/opencode2/oh-my-opencode-slim.json.tmpl"
OMO="${H}/dot_omo/modify_omo.jsonc"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

TEST_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT
DEST="${TEST_ROOT}/destination"
TEST_HOME="${TEST_ROOT}/home"
EMPTY_CONFIG="${TEST_ROOT}/chezmoi-empty.json"
mkdir -p "$DEST" "$TEST_HOME/.config/opencode"
printf '{}\n' > "$EMPTY_CONFIG"

# A shim `bws` earlier on PATH plus a fake wrapper make "BWS usable" without
# touching real secrets. The wrapper echoes a value derived from the id.
SHIMS="${TEST_ROOT}/shims"
mkdir -p "$SHIMS" "$TEST_HOME/.local/lib"
printf '#!/bin/sh\nexit 0\n' > "$SHIMS/bws"
printf '#!/bin/sh\nprintf "secret-for-%%s" "$1"\n' > "$TEST_HOME/.local/lib/bws-get-or-empty"
chmod +x "$SHIMS/bws" "$TEST_HOME/.local/lib/bws-get-or-empty"
printf 'fake-token\n' > "$TEST_HOME/token"

# render <template> <overrides-json> [stdin]
render() {
  local template=$1 overrides=$2 existing=${3-'{}'}
  local data="${TEST_ROOT}/data.json"
  jq -n --arg home "$TEST_HOME" --argjson o "$overrides" '
    {machineProfile: "personal", chezmoi: {homeDir: $home},
     openCodeWorkPlugin: "", npmWorkRegistry: "",
     bwsTokenPath: ($home + "/missing-token")} * $o' > "$data"
  printf '%s\n' "$existing" |
    PATH="${SHIMS}:${PATH}" chezmoi execute-template --config "$EMPTY_CONFIG" -S "$ROOT" -D "$DEST" \
      --override-data-file "$data" --with-stdin -f "$template"
}

PROFILES=$(chezmoi execute-template --config "$EMPTY_CONFIG" -S "$ROOT" -D "$DEST" '{{ .mcpproxyProfiles | toJson }}')
LANES=$(jq -c '["mp-codemode"] + [.[].name | "mp-" + .] | sort' <<< "$PROFILES")
jq -e 'all(.[]; .name != "flows") and ([.[].servers[]] | index("smithers") | not)' <<< "$PROFILES" >/dev/null ||
  fail "smithers/flows still present in profiles"

# --- MCPProxy server set per os x machine profile -----------------------------
for os in darwin linux; do
  for profile in work personal; do
    o=$(jq -nc --arg os "$os" --arg p "$profile" '{chezmoi: {os: $os}, machineProfile: $p}')
    proxy=$(render "$MCPPROXY" "$o")
    expected='["chrome-devtools","context7","figma-desktop","gh_grep","notion","pdf-tools","websearch"]'
    [ "$profile" = work ] && expected=$(jq -c '. + ["otter"] | sort' <<< "$expected")
    jq -e --argjson e "$expected" '[.mcpServers[].name] | sort == $e' <<< "$proxy" >/dev/null ||
      fail "MCPProxy server set wrong for ${os}/${profile}: $(jq -c '[.mcpServers[].name]' <<< "$proxy")"
    jq -e 'all(.mcpServers[]; .trust_mode == "auto" and .enabled == true)' <<< "$proxy" >/dev/null ||
      fail "trust_mode/enabled missing for ${os}/${profile}"
    jq -e 'all(.mcpServers[]; has("when") or has("trust") or has("envSecrets") or has("headerSecrets") | not)' \
      <<< "$proxy" >/dev/null || fail "catalogue meta keys leaked into MCPProxy for ${os}/${profile}"
    jq -e --argjson p "$PROFILES" '.profiles == $p' <<< "$proxy" >/dev/null ||
      fail "MCPProxy profiles differ from shared data for ${os}/${profile}"
    again=$(render "$MCPPROXY" "$o" "$proxy")
    [ "$again" = "$proxy" ] || fail "MCPProxy render not stable for ${os}/${profile}"

    # Every client: identical lane names.
    jq -e --argjson l "$LANES" '.mcp | keys == $l and
      .["mp-codemode"] == {type: "remote", enabled: true, url: "http://127.0.0.1:18321/mcp/"}' \
      <<< "$(render "$OC1" "$o")" >/dev/null || fail "OpenCode 1 lanes wrong for ${os}/${profile}"
    jq -e --argjson l "$LANES" '.mcp.servers | keys == $l and
      .["mp-docs"] == {type: "remote", url: "http://127.0.0.1:18321/mcp/p/docs", disabled: false}' \
      <<< "$(render "$OC2" "$o")" >/dev/null || fail "OpenCode 2 lanes wrong for ${os}/${profile}"
    jq -e --argjson l "$LANES" '.mcpServers | keys == $l and
      .["mp-research"] == {type: "http", url: "http://127.0.0.1:18321/mcp/p/research"}' \
      <<< "$(render "$CLAUDE" "$o")" >/dev/null || fail "Claude Code lanes wrong for ${os}/${profile}"
    jq -e --argjson l "$LANES" '.mcpServers | keys == $l and
      .["mp-codemode"] == {command: "npx", args: ["-y", "mcp-remote", "http://127.0.0.1:18321/mcp/"]}' \
      <<< "$(render "$DESKTOP" "$o")" >/dev/null || fail "Claude Desktop lanes wrong for ${os}/${profile}"
    codex_lanes=$(render "$CODEX" "$o" "" | grep -E '^\[mcp_servers\.' | sed -E 's/^\[mcp_servers\.([^]]+)\]$/\1/' | jq -Rsc 'split("\n") | map(select(. != "")) | sort')
    [ "$codex_lanes" = "$LANES" ] || fail "Codex lanes wrong for ${os}/${profile}: ${codex_lanes}"

    # Plugin built-ins the proxy serves are disabled on every profile.
    jq -e '.disabled_mcps == ["context7", "gh_grep"]' <<< "$(render "$SLIM" "$o")" >/dev/null ||
      fail "slim disabled_mcps wrong for ${os}/${profile}"
    jq -e '.["[opencode]"].disabled_mcps == ["context7", "grep_app", "websearch"]' \
      <<< "$(render "$OMO" "$o")" >/dev/null || fail "OMO disabled_mcps wrong for ${os}/${profile}"
  done
done
printf 'PASS: catalogue conditions and identical lanes for every client (darwin/linux x work/personal)\n'

# --- Secrets: resolved from BWS ids only in MCPProxy; pushbullet gated --------
o=$(jq -nc --arg t "$TEST_HOME/token" '{machineProfile: "personal", bwsTokenPath: $t,
  bwsIdPushbulletAccessToken: "id-pb", bwsIdContext7ApiKey: "id-c7", bwsIdExaApiKey: "id-exa"}')
proxy=$(render "$MCPPROXY" "$o")
jq -e --arg home "$TEST_HOME" '
  (.mcpServers | map({key: .name, value: .}) | from_entries) as $s |
  $s.pushbullet == {name: "pushbullet", command: ($home + "/.local/bin/pushbullet-mcp"), args: [],
    protocol: "stdio", enabled: true, env: {PUSHBULLET_ACCESS_TOKEN: "secret-for-id-pb"}} and
  $s.context7.headers == {CONTEXT7_API_KEY: "secret-for-id-c7"} and
  $s.websearch.headers == {"x-api-key": "secret-for-id-exa"}
' <<< "$proxy" >/dev/null || fail "secret resolution or pushbullet trust exemption wrong: $(jq -c '.mcpServers' <<< "$proxy")"
o=$(jq -nc --arg t "$TEST_HOME/token" '{bwsTokenPath: $t, bwsIdPushbulletAccessToken: ""}')
render "$MCPPROXY" "$o" | jq -e '[.mcpServers[].name] | index("pushbullet") | not' >/dev/null ||
  fail "pushbullet registered without a resolvable token"
for t in "$OC1" "$CLAUDE" "$OMO" "$SLIM"; do
  if render "$t" "$(jq -nc --arg t "$TEST_HOME/token" '{bwsTokenPath: $t, bwsIdContext7ApiKey: "id-c7"}')" | grep -q 'secret-for-'; then
    fail "client projection resolved a secret: ${t}"
  fi
done
printf 'PASS: BWS secrets resolve into MCPProxy only; pushbullet gated and untrusted\n'

# --- Machine-local additions ------------------------------------------------
o='{"mcpServersLocal": {"local-http": {"url": "https://mcp.example.invalid/mcp", "headers": {"x": "y"}},
                        "local-cmd": {"command": "example-mcp", "trust": "none"}},
    "mcpStdioServers": {"legacy": {"command": "legacy-mcp", "args": ["serve"]}}}'
proxy=$(render "$MCPPROXY" "$o")
jq -e '
  (.mcpServers | map({key: .name, value: .}) | from_entries) as $s |
  $s["local-http"] == {name: "local-http", url: "https://mcp.example.invalid/mcp", headers: {x: "y"},
    protocol: "http", enabled: true, trust_mode: "auto"} and
  $s["local-cmd"] == {name: "local-cmd", command: "example-mcp", args: [], protocol: "stdio", enabled: true} and
  $s.legacy == {name: "legacy", command: "legacy-mcp", args: ["serve"], protocol: "stdio", enabled: true, trust_mode: "auto"}
' <<< "$proxy" >/dev/null || fail "local additions not merged: $(jq -c '.mcpServers' <<< "$proxy")"
for bad in '{"mcpServersLocal": {"context7": {"url": "https://x.invalid"}}}' \
  '{"mcpStdioServers": {"notion": {"command": "x"}}}' \
  '{"mcpServersLocal": {"dup": {"command": "a"}}, "mcpStdioServers": {"dup": {"command": "b"}}}' \
  '{"mcpStdioServers": {"nocmd": {"args": []}}}' \
  '{"mcpServersLocal": {"empty": {"args": []}}}'; do
  if render "$MCPPROXY" "$bad" >/dev/null 2>&1; then
    fail "invalid local addition was accepted: ${bad}"
  fi
done
# A local addition joins no lane by itself, so clients are unchanged.
[ "$(render "$OC2" "$o" | jq -c '.mcp.servers | keys')" = "$LANES" ] || fail "local addition changed client lanes"
printf 'PASS: local additions merge; catalogue-name conflicts and malformed entries fail\n'

# --- Claude Code: only top-level mcpServers is replaced ------------------------
existing='{"mcpServers": {"mcpproxy": {"command": "npx"}}, "projects": {"/p": {"mcpServers": {"keep": {"type": "stdio", "command": "k"}}}}, "other": 1}'
render "$CLAUDE" '{}' "$existing" | jq -e --argjson l "$LANES" '
  (.mcpServers | keys) == $l and .projects == {"/p": {mcpServers: {keep: {type: "stdio", command: "k"}}}} and .other == 1
' >/dev/null || fail "Claude Code touched projects.*.mcpServers or other keys"
printf 'PASS: Claude Code keeps per-project MCP servers\n'

# --- Codex: one-time legacy migration, foreign tables kept, stable ------------
legacy=$(cat <<'TOML'
# --- BEGIN CHEZMOI MANAGED SECTION ---
# This section is managed by chezmoi. Do not edit manually.
# Keys set by Codex CLI (model, projects, notice, etc.) are preserved
# outside this section and will not be overwritten.

model_instructions_file = "/home/example/.codex/instructions.md"

notify = ["notifier", "turn-ended"]
model = "example-model"

[features]
codex_hooks = true
js_repl = false

[mcp_servers.mcpproxy]
url = "http://127.0.0.1:18321/mcp/"

[mcp_servers.mcpproxy.tools.call_tool_write]
approval_mode = "approve"
# --- END CHEZMOI MANAGED SECTION ---


[mcp_servers.Canva]
type = "http"
url = "https://mcp.canva.com/mcp"

[projects."/home/example/dev"]
trust_level = "trusted"
TOML
)
first=$(render "$CODEX" '{}' "$legacy")
python3 - "$first" "$LANES" <<'PY' || fail "Codex migration produced the wrong TOML"
import json, sys, tomllib
doc = tomllib.loads(sys.argv[1]); lanes = json.loads(sys.argv[2])
assert doc["model_instructions_file"] == "/home/example/.codex/instructions.md"
assert doc["notify"] == ["notifier", "turn-ended"] and doc["model"] == "example-model"
assert doc["features"] == {"codex_hooks": True, "js_repl": False}
servers = doc["mcp_servers"]
assert "mcpproxy" not in servers, servers
assert sorted(servers) == sorted(lanes + ["Canva"]), sorted(servers)
assert servers["mp-codemode"] == {"url": "http://127.0.0.1:18321/mcp/",
    "tools": {"call_tool_write": {"approval_mode": "approve"}}}
assert servers["Canva"] == {"type": "http", "url": "https://mcp.canva.com/mcp"}
assert doc["projects"] == {"/home/example/dev": {"trust_level": "trusted"}}
PY
grep -q 'Keys set by Codex CLI' <<< "$first" && fail "Codex migration kept the old header comments"
[ "$(grep -c 'BEGIN CHEZMOI MANAGED SECTION' <<< "$first")" = 1 ] || fail "Codex render has more than one managed section"
second=$(render "$CODEX" '{}' "$first")
[ "$second" = "$first" ] || fail "Codex render is not stable after migration"
fresh=$(render "$CODEX" '{}' "")
python3 -c 'import sys, tomllib; tomllib.loads(sys.argv[1])' "$fresh" || fail "fresh Codex render is not TOML"
[ "$(render "$CODEX" '{}' "$fresh")" = "$fresh" ] || fail "fresh Codex render is not stable"
printf 'PASS: Codex legacy block salvaged and renamed, foreign tables kept, re-render stable\n'

# --- Re-init carries the machine-local MCP tables ------------------------------
jq -n '{data: {
  mcpServersLocal: {"local-http": {url: "https://mcp.example.invalid/mcp", headers: {x: "y"}}},
  mcpStdioServers: {legacy: {command: "legacy-mcp", args: ["serve"], env: {A: "b"}}}}}' > "${TEST_ROOT}/init.json"
chezmoi execute-template --init --no-tty --config "${TEST_ROOT}/init.json" \
  -S "$ROOT" -D "$DEST" -f "${H}/.chezmoi.toml.tmpl" > "${TEST_ROOT}/config.toml"
for table in mcpServersLocal mcpStdioServers; do
  [ "$(chezmoi execute-template --config "${TEST_ROOT}/config.toml" -S "$ROOT" -D "$DEST" "{{ .${table} | toJson }}" | jq -S -c .)" = \
    "$(jq -S -c --arg t "$table" '.data[$t]' "${TEST_ROOT}/init.json")" ] ||
    fail "config-template rendering did not carry [data.${table}] across re-init"
done
chezmoi execute-template --init --no-tty --config "${TEST_ROOT}/config.toml" \
  -S "$ROOT" -D "$DEST" -f "${H}/.chezmoi.toml.tmpl" | cmp -s - "${TEST_ROOT}/config.toml" ||
  fail "config-template rendering of MCP tables is not stable across re-init"
printf 'PASS: config-template carries mcpServersLocal and mcpStdioServers across re-init\n'
