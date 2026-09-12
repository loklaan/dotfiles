#!/usr/bin/env bash
# shellcheck disable=SC2016

#|----------------------------------------------------------------------------|
#| OpenCode auth privacy regression tests                                     |
#|                                                                            |
#| Run: bash tests/security-integrations/opencode-auth.test.sh                 |
#|                                                                            |
#| The harness renders the lifecycle script into an isolated HOME and fakes   |
#| BWS entirely. It never invokes chezmoi apply/init or contacts Bitwarden.    |
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

make_fake() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  printf '#!/usr/bin/env bash\n%s\n' "$*" > "$path"
  chmod 755 "$path"
}

file_mode() {
  if [[ "$(uname -s)" == Darwin ]]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

render_script() {
  local output="$1"
  chezmoi execute-template -S "$REPO/home" \
    --override-data '{"chezmoi":{"os":"linux"},"bwsTokenPath":"/fixture/token","bwsIdOpencodeApiKey":"fixture-secret"}' \
    --file "$REPO/home/.chezmoiscripts/run_after_install-065-opencode-auth.sh.tmpl" > "$output"
  chmod 755 "$output"
}

prepare_home() {
  local home="$1"
  mkdir -p "$home/.local/lib" "$home/.cache/dotfiles/logs" "$home/shims"
  chmod 700 "$home/.cache/dotfiles" "$home/.cache/dotfiles/logs"
  cp "$REPO/home/private_dot_local/lib/bash-logging.sh" "$home/.local/lib/"
  cp "$REPO/home/private_dot_local/lib/term-colour.sh" "$home/.local/lib/"
  make_fake "$home/.local/lib/bws-get-or-empty" 'printf "%s" "${TEST_API_KEY:-}"'
  make_fake "$home/shims/jq" '
printf "%s\n" "$$" > "$TEST_JQ_PID_FILE"
sleep 0.5
exec "$TEST_REAL_JQ" "$@"'
  render_script "$home/opencode-auth.sh"
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

process_argv() {
  local pid="$1"
  if [[ -r "/proc/$pid/cmdline" ]]; then
    tr '\0' ' ' < "/proc/$pid/cmdline"
  else
    ps -p "$pid" -o command=
  fi
}

logs_contain() {
  local home="$1" text="$2"
  local log
  local nullglob_was_set=0
  shopt -q nullglob && nullglob_was_set=1
  shopt -s nullglob
  for log in "$home"/.cache/dotfiles/logs/*.log*; do
    if grep -qF "$text" "$log"; then
      [[ "$nullglob_was_set" -eq 1 ]] || shopt -u nullglob
      return 0
    fi
  done
  [[ "$nullglob_was_set" -eq 1 ]] || shopt -u nullglob
  return 1
}

run_sync() {
  local home="$1" key="$2" output="$3"
  local pid jq_pid argv path
  local -a intermediates
  rm -f "$home/jq.pid"
  (
    umask 022
    env HOME="$home" DEBUG=1 TEST_API_KEY="$key" TEST_REAL_JQ="$REAL_JQ" \
      TEST_JQ_PID_FILE="$home/jq.pid" PATH="$home/shims:$PATH" \
      bash "$home/opencode-auth.sh"
  ) > "$output" 2>&1 &
  pid=$!

  if wait_for_file "$home/jq.pid"; then
    jq_pid=$(<"$home/jq.pid")
    argv="$(process_argv "$jq_pid")"
    if [[ "$argv" == *"$key"* ]]; then
      no "API key is absent from jq process argv"
    else
      ok "API key is absent from jq process argv"
    fi

    shopt -s nullglob
    intermediates=("$home"/.local/share/opencode/.opencode-auth*)
    shopt -u nullglob
    check "both merge intermediates are observable" "${#intermediates[@]}" 2
    for path in "${intermediates[@]}"; do
      check "merge intermediate $(basename "$path") is 0600" "$(file_mode "$path")" 600
    done
  else
    no "jq process became observable"
  fi

  if wait "$pid"; then
    ok "auth sync exits successfully"
  else
    no "auth sync exits successfully"
  fi
}

SOURCE="$REPO/home/.chezmoiscripts/run_after_install-065-opencode-auth.sh.tmpl"
AUTH_SOURCE="$REPO/home/private_dot_local/share/opencode/private_auth.json.tmpl"

printf '\nsource hardening\n'
if grep -q -- '--arg key' "$SOURCE"; then
  no "jq secret handoff is absent from command arguments"
else
  ok "jq secret handoff is absent from command arguments"
fi
if [[ -f "$AUTH_SOURCE" ]]; then
  ok "managed auth seed has chezmoi private_ attribute"
else
  no "managed auth seed has chezmoi private_ attribute"
fi

printf '\nfirst run under umask 022\n'
HOME_SYNC="$ROOT/sync"
prepare_home "$HOME_SYNC"
FIRST_KEY="opencode-first-regression-key"
run_sync "$HOME_SYNC" "$FIRST_KEY" "$HOME_SYNC/first.output"
AUTH_FILE="$HOME_SYNC/.local/share/opencode/auth.json"
check "first-run auth file is 0600" "$(file_mode "$AUTH_FILE")" 600
check "first run writes opencode key" "$("$REAL_JQ" -r '.opencode.key' "$AUTH_FILE")" "$FIRST_KEY"
check "first run writes opencode-go key" "$("$REAL_JQ" -r '."opencode-go".key' "$AUTH_FILE")" "$FIRST_KEY"
if grep -qF "$FIRST_KEY" "$HOME_SYNC/first.output" || logs_contain "$HOME_SYNC" "$FIRST_KEY"; then
  no "first key is absent from output and logs with DEBUG=1"
else
  ok "first key is absent from output and logs with DEBUG=1"
fi

printf '\nsecond run preserves unrelated providers\n'
cat > "$AUTH_FILE" <<'EOF'
{
  "google": {"type":"oauth","refresh":"google-refresh","nested":{"order":[3,2,1]}},
  "openai": {"type":"api","key":"llmproxy","extra":true},
  "amazon-bedrock": {"type":"api","key":"llmproxy","region":"global"},
  "opencode": {"type":"api","key":"old"},
  "opencode-go": {"type":"api","key":"old"}
}
EOF
chmod 600 "$AUTH_FILE"
PROVIDERS_BEFORE="$("$REAL_JQ" -c '[.google,.openai,."amazon-bedrock"]' "$AUTH_FILE")"
SECOND_KEY="opencode-second-regression-key"
run_sync "$HOME_SYNC" "$SECOND_KEY" "$HOME_SYNC/second.output"
check "second-run auth file is 0600" "$(file_mode "$AUTH_FILE")" 600
check "second run updates both opencode keys" \
  "$("$REAL_JQ" -r '[.opencode.key,."opencode-go".key] | unique | join("")' "$AUTH_FILE")" "$SECOND_KEY"
check "second run preserves google/openai/amazon-bedrock values" \
  "$("$REAL_JQ" -c '[.google,.openai,."amazon-bedrock"]' "$AUTH_FILE")" "$PROVIDERS_BEFORE"
if grep -qF "$SECOND_KEY" "$HOME_SYNC/second.output" || logs_contain "$HOME_SYNC" "$SECOND_KEY"; then
  no "second key is absent from output and logs with DEBUG=1"
else
  ok "second key is absent from output and logs with DEBUG=1"
fi

printf '\nmissing key soft-fails without modification\n'
AUTH_HASH_BEFORE="$(shasum -a 256 "$AUTH_FILE" | cut -d ' ' -f 1)"
if env HOME="$HOME_SYNC" DEBUG=1 TEST_API_KEY='' TEST_REAL_JQ="$REAL_JQ" \
  TEST_JQ_PID_FILE="$HOME_SYNC/jq.pid" PATH="$HOME_SYNC/shims:$PATH" \
  bash "$HOME_SYNC/opencode-auth.sh" > "$HOME_SYNC/empty.output" 2>&1; then
  ok "empty key exits successfully"
else
  no "empty key exits successfully"
fi
check "empty key leaves auth file unchanged" \
  "$(shasum -a 256 "$AUTH_FILE" | cut -d ' ' -f 1)" "$AUTH_HASH_BEFORE"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
