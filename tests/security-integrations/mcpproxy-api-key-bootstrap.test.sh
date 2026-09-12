#!/usr/bin/env bash
# shellcheck disable=SC2016

#|----------------------------------------------------------------------------|
#| MCPProxy api_key bootstrap regression tests                                |
#|                                                                            |
#| Run: bash tests/security-integrations/mcpproxy-api-key-bootstrap.test.sh    |
#|                                                                            |
#| The harness renders run_before_install-056-generate-mcpproxy-api-key.sh    |
#| into isolated HOME fixtures and never touches the real ~/.mcpproxy. It     |
#| never invokes chezmoi apply/init.                                           |
#|----------------------------------------------------------------------------|

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(mktemp -d)"
REAL_JQ="$(command -v jq)"
PASS=0
FAIL=0
trap 'rm -rf "$ROOT"' EXIT

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }

file_mode() {
  if [[ "$(uname -s)" == Darwin ]]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

render_script() {
  local output="$1"
  # Deliberately no --override-data: .chezmoi.sourceDir must resolve to the
  # REAL repo source tree, exactly as it does in production, since the
  # script's whole point is sourcing bash-logging.sh from there rather than
  # from the fixture HOME's (nonexistent) ~/.local/lib.
  chezmoi execute-template -S "$REPO/home" \
    --file "$REPO/home/.chezmoiscripts/run_before_install-056-generate-mcpproxy-api-key.sh.tmpl" > "$output"
  chmod 755 "$output"
}

prepare_home() {
  local home="$1"
  mkdir -p "$home/.cache/dotfiles/logs" "$home/shims"
  chmod 700 "$home/.cache/dotfiles" "$home/.cache/dotfiles/logs"
}

process_argv() {
  local pid="$1"
  if [[ -r "/proc/$pid/cmdline" ]]; then
    tr '\0' ' ' < "/proc/$pid/cmdline"
  else
    ps -p "$pid" -o command=
  fi
}

wait_for_file() {
  local path="$1"
  local _
  for _ in {1..100}; do
    [[ -s "$path" ]] && return 0
    sleep 0.01
  done
  return 1
}

SOURCE="$REPO/home/.chezmoiscripts/run_before_install-056-generate-mcpproxy-api-key.sh.tmpl"
RENDERED="$ROOT/generate-key.sh"
render_script "$RENDERED"

printf '\nsource hardening\n'
if grep -q -- '--arg' "$SOURCE"; then
  no "jq secret handoff is absent from command arguments"
else
  ok "jq secret handoff is absent from command arguments"
fi
if grep -q 'openssl rand' "$SOURCE"; then
  no "generation avoids openssl (portability)"
else
  ok "generation avoids openssl (portability)"
fi
if grep -q '{{ \.chezmoi\.sourceDir }}' "$SOURCE"; then
  ok "sources bash-logging.sh from chezmoi source tree, not ~/.local/lib"
else
  no "sources bash-logging.sh from chezmoi source tree, not ~/.local/lib"
fi

printf '\nfresh machine: no ~/.mcpproxy directory at all\n'
HOME_FRESH="$ROOT/fresh"
mkdir -p "$HOME_FRESH"
prepare_home "$HOME_FRESH"
CONFIG_FRESH="$HOME_FRESH/.mcpproxy/mcp_config.json"

if env HOME="$HOME_FRESH" PATH="$PATH" bash "$RENDERED" > "$HOME_FRESH/run.output" 2>&1; then
  ok "fresh-machine run exits successfully"
else
  no "fresh-machine run exits successfully"
  cat "$HOME_FRESH/run.output" >&2
fi
check "fresh-machine .mcpproxy dir mode is 0700" "$(file_mode "$HOME_FRESH/.mcpproxy")" 700
check "fresh-machine mcp_config.json mode is 0600" "$(file_mode "$CONFIG_FRESH")" 600
FRESH_KEY="$("$REAL_JQ" -r '.api_key' "$CONFIG_FRESH")"
if [[ "$FRESH_KEY" =~ ^[0-9a-f]{64}$ ]]; then
  ok "generated api_key is 64-char lowercase hex"
else
  no "generated api_key is 64-char lowercase hex (got '$FRESH_KEY')"
fi
if grep -qF "$FRESH_KEY" "$HOME_FRESH/run.output"; then
  no "generated key value is absent from script output"
else
  ok "generated key value is absent from script output"
fi
check "fresh-machine config has exactly one field" "$("$REAL_JQ" -r 'keys | length' "$CONFIG_FRESH")" 1

printf '\nexisting config with non-empty api_key: complete no-op, run twice\n'
HOME_NOOP="$ROOT/noop"
mkdir -p "$HOME_NOOP/.mcpproxy"
chmod 700 "$HOME_NOOP/.mcpproxy"
prepare_home "$HOME_NOOP"
CONFIG_NOOP="$HOME_NOOP/.mcpproxy/mcp_config.json"
EXISTING_KEY="preexisting-mcpproxy-regression-key-0123456789abcdef0123456789ab"
"$REAL_JQ" -n --arg key "$EXISTING_KEY" '{api_key: $key, unrelated: "preserved"}' > "$CONFIG_NOOP"
chmod 600 "$CONFIG_NOOP"
HASH_BEFORE="$(shasum -a 256 "$CONFIG_NOOP" | cut -d ' ' -f1)"

if env HOME="$HOME_NOOP" DEBUG=1 PATH="$PATH" bash "$RENDERED" > "$HOME_NOOP/run1.output" 2>&1; then
  ok "first no-op run exits successfully"
else
  no "first no-op run exits successfully"
  cat "$HOME_NOOP/run1.output" >&2
fi
check "first no-op run: file byte-for-byte unchanged" \
  "$(shasum -a 256 "$CONFIG_NOOP" | cut -d ' ' -f1)" "$HASH_BEFORE"
check "first no-op run: key preserved (not regenerated)" \
  "$("$REAL_JQ" -r '.api_key' "$CONFIG_NOOP")" "$EXISTING_KEY"
if grep -qF "$EXISTING_KEY" "$HOME_NOOP/run1.output"; then
  no "DEBUG=1 existing-key probe keeps the credential out of output"
else
  ok "DEBUG=1 existing-key probe keeps the credential out of output"
fi
if grep -qF "Generated mcpproxy api_key" "$HOME_NOOP/run1.output"; then
  no "no-op run logs no generation message"
else
  ok "no-op run logs no generation message"
fi

if env HOME="$HOME_NOOP" PATH="$PATH" bash "$RENDERED" > "$HOME_NOOP/run2.output" 2>&1; then
  ok "second no-op run exits successfully"
else
  no "second no-op run exits successfully"
  cat "$HOME_NOOP/run2.output" >&2
fi
check "second no-op run: file still byte-for-byte unchanged" \
  "$(shasum -a 256 "$CONFIG_NOOP" | cut -d ' ' -f1)" "$HASH_BEFORE"
check "second no-op run: identical key both times" \
  "$("$REAL_JQ" -r '.api_key' "$CONFIG_NOOP")" "$EXISTING_KEY"

printf '\nexisting config missing api_key: merges, preserves other keys\n'
HOME_MERGE="$ROOT/merge"
mkdir -p "$HOME_MERGE/.mcpproxy"
chmod 700 "$HOME_MERGE/.mcpproxy"
prepare_home "$HOME_MERGE"
CONFIG_MERGE="$HOME_MERGE/.mcpproxy/mcp_config.json"
"$REAL_JQ" -n '{listen:"127.0.0.1:1234",data_dir:"/x",mcpServers:[{name:"context7",quarantined:true}],require_mcp_auth:true}' \
  > "$CONFIG_MERGE"
chmod 600 "$CONFIG_MERGE"
OTHER_BEFORE="$("$REAL_JQ" -c '{listen, data_dir, mcpServers, require_mcp_auth}' "$CONFIG_MERGE")"

if env HOME="$HOME_MERGE" PATH="$PATH" bash "$RENDERED" > "$HOME_MERGE/merge.output" 2>&1; then
  ok "merge run exits successfully"
else
  no "merge run exits successfully"
  cat "$HOME_MERGE/merge.output" >&2
fi
check "merge run: config mode remains 0600" "$(file_mode "$CONFIG_MERGE")" 600
MERGED_KEY="$("$REAL_JQ" -r '.api_key' "$CONFIG_MERGE")"
if [[ "$MERGED_KEY" =~ ^[0-9a-f]{64}$ ]]; then
  ok "merge run: api_key added as 64-char lowercase hex"
else
  no "merge run: api_key added as 64-char lowercase hex (got '$MERGED_KEY')"
fi
check "merge run: every other pre-existing key preserved untouched" \
  "$("$REAL_JQ" -c '{listen, data_dir, mcpServers, require_mcp_auth}' "$CONFIG_MERGE")" "$OTHER_BEFORE"

printf '\nre-running after merge never rotates the newly merged key\n'
REMERGE_HASH_BEFORE="$(shasum -a 256 "$CONFIG_MERGE" | cut -d ' ' -f1)"
if env HOME="$HOME_MERGE" PATH="$PATH" bash "$RENDERED" > "$HOME_MERGE/remerge.output" 2>&1; then
  ok "post-merge re-run exits successfully"
else
  no "post-merge re-run exits successfully"
fi
check "post-merge re-run: file byte-for-byte unchanged" \
  "$(shasum -a 256 "$CONFIG_MERGE" | cut -d ' ' -f1)" "$REMERGE_HASH_BEFORE"
check "post-merge re-run: same key value" "$("$REAL_JQ" -r '.api_key' "$CONFIG_MERGE")" "$MERGED_KEY"

printf '\napi_key never appears on any subprocess argv\n'
HOME_ARGV="$ROOT/argv"
mkdir -p "$HOME_ARGV"
prepare_home "$HOME_ARGV"
cat > "$HOME_ARGV/shims/jq" <<'SHIM'
#!/usr/bin/env bash
printf "%s\n" "$$" > "$TEST_JQ_PID_FILE"
sleep 0.3
exec "$TEST_REAL_JQ" "$@"
SHIM
chmod 755 "$HOME_ARGV/shims/jq"
rm -f "$HOME_ARGV/jq.pid"

(
  env HOME="$HOME_ARGV" TEST_REAL_JQ="$REAL_JQ" TEST_JQ_PID_FILE="$HOME_ARGV/jq.pid" \
    PATH="$HOME_ARGV/shims:$PATH" bash "$RENDERED"
) > "$HOME_ARGV/argv.output" 2>&1 &
ARGV_PID=$!

if wait_for_file "$HOME_ARGV/jq.pid"; then
  JQ_PID="$(<"$HOME_ARGV/jq.pid")"
  ARGV="$(process_argv "$JQ_PID")"
  wait "$ARGV_PID" || true
  GENERATED_KEY="$("$REAL_JQ" -r '.api_key // ""' "$HOME_ARGV/.mcpproxy/mcp_config.json" 2>/dev/null || echo "")"
  if [[ -n "$GENERATED_KEY" ]] && [[ "$ARGV" == *"$GENERATED_KEY"* ]]; then
    no "api_key is absent from jq process argv"
  else
    ok "api_key is absent from jq process argv"
  fi
else
  no "jq process became observable"
  wait "$ARGV_PID" || true
fi

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
