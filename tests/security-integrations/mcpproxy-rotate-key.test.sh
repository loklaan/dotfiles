#!/usr/bin/env bash
# shellcheck disable=SC2016

#|----------------------------------------------------------------------------|
#| MCPProxy headless key rotation tests                                       |
#|                                                                            |
#| Run: bash tests/security-integrations/mcpproxy-rotate-key.test.sh          |
#|----------------------------------------------------------------------------|

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(mktemp -d)"
PASS=0
FAIL=0
REAL_JQ="$(command -v jq)"
if [ -L "$REAL_JQ" ] && command -v mise >/dev/null 2>&1; then
  REAL_JQ="$(mise which jq 2>/dev/null || printf '%s' "$REAL_JQ")"
fi
SCRIPT_PATH="$(dirname "$REAL_JQ"):$PATH"
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

prepare_home() {
  local home="$1"
  mkdir -p "$home/.local/lib" "$home/.mcpproxy" "$home/shims"
  cp "$REPO/home/private_dot_local/lib/bash-logging.sh" "$home/.local/lib/"
  cp "$REPO/home/private_dot_local/lib/term-colour.sh" "$home/.local/lib/"
  jq -n --arg key 'old-rotation-test-key' '{
    listen: "127.0.0.1:18321",
    api_key: $key,
    require_mcp_auth: true,
    mcpServers: [],
    telemetry: {enabled: false}
  }' > "$home/.mcpproxy/mcp_config.json"
  chmod 600 "$home/.mcpproxy/mcp_config.json"

  cat > "$home/shims/chezmoi" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
key=$(jq -r '.api_key' "$HOME/.mcpproxy/mcp_config.json")
printf 'Authorization: Bearer %s\n' "$key" > "$HOME/.mcpproxy/mcp-client-headers"
chmod 600 "$HOME/.mcpproxy/mcp-client-headers"
touch "$HOME/chezmoi-called"
SHIM

  cat > "$home/shims/pitchfork" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  list) printf 'global/df-mcpproxy running\n' ;;
  restart) touch "$HOME/pitchfork-restarted" ;;
esac
SHIM

  cat > "$home/shims/curl" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
hdr=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -H) shift; hdr="${1:-}" ;;
    --data | --max-time | -o | -w) shift ;;
    http://*/ready | http://*) url="$1" ;;
  esac
  shift
done
case "$url" in
  */ready) printf '200'; exit 0 ;;
esac
if [ -f "$HOME/fail-verify" ]; then
  printf '401'
  exit 0
fi
if [ "$hdr" = "@$HOME/.mcpproxy/mcp-client-headers" ]; then
  printf '200'
else
  printf '401'
fi
SHIM

  chmod 755 "$home/shims/chezmoi" "$home/shims/pitchfork" "$home/shims/curl"
}

rotate() {
  local home="$1"
  shift
  env HOME="$home" PATH="$home/shims:$SCRIPT_PATH" \
    bash "$REPO/home/private_dot_local/bin/executable_df-mcpproxy-rotate-key" "$@"
}

key_of() {
  jq -r '.api_key' "$1/.mcpproxy/mcp_config.json"
}

phase_of() {
  jq -r '.phase // ""' "$1/.local/state/dotfiles/mcpproxy/rotation.json"
}

printf '\nheadless rotation rotates, renders, restarts and verifies\n'
HOME_OK="$ROOT/ok"
prepare_home "$HOME_OK"
OLD_KEY="$(key_of "$HOME_OK")"
if rotate "$HOME_OK" > "$HOME_OK/output" 2>&1; then
  ok "rotation exits successfully"
else
  no "rotation exits successfully"
  cat "$HOME_OK/output" >&2
fi
NEW_KEY="$(key_of "$HOME_OK")"
if [[ -n "$NEW_KEY" && "$NEW_KEY" != "$OLD_KEY" ]]; then
  ok "rotation changes the key"
else
  no "rotation changes the key"
fi
check "config is private" "$(file_mode "$HOME_OK/.mcpproxy/mcp_config.json")" 600
check "header file is private" "$(file_mode "$HOME_OK/.mcpproxy/mcp-client-headers")" 600
check "header file carries the new key" "$(cat "$HOME_OK/.mcpproxy/mcp-client-headers")" "Authorization: Bearer $NEW_KEY"
check "receipt reaches verified" "$(phase_of "$HOME_OK")" verified
if [[ -e "$HOME_OK/chezmoi-called" ]]; then ok "clients were rendered"; else no "clients were rendered"; fi
if [[ -e "$HOME_OK/pitchfork-restarted" ]]; then ok "daemon was restarted"; else no "daemon was restarted"; fi
if grep -qF "$NEW_KEY" "$HOME_OK/output"; then
  no "key is absent from command output"
else
  ok "key is absent from command output"
fi

printf '\na second run rotates again\n'
FIRST_KEY="$NEW_KEY"
if rotate "$HOME_OK" > "$HOME_OK/output2" 2>&1; then
  ok "second rotation exits successfully"
else
  no "second rotation exits successfully"
  cat "$HOME_OK/output2" >&2
fi
SECOND_KEY="$(key_of "$HOME_OK")"
if [[ "$SECOND_KEY" != "$FIRST_KEY" ]]; then
  ok "second run generates another key"
else
  no "second run generates another key"
fi
if grep -qF "$SECOND_KEY" "$HOME_OK/output2"; then
  no "second key is absent from command output"
else
  ok "second key is absent from command output"
fi

printf '\ncheck signals health and if-due is a no-op when healthy\n'
if rotate "$HOME_OK" --check > "$HOME_OK/check-ok" 2>&1; then
  ok "healthy key passes --check"
else
  no "healthy key passes --check"
  cat "$HOME_OK/check-ok" >&2
fi
grep -q 'status ok' "$HOME_OK/check-ok" || no "healthy check reports status ok"
BEFORE_IF_DUE="$(key_of "$HOME_OK")"
if rotate "$HOME_OK" --if-due > "$HOME_OK/if-due-ok" 2>&1; then
  ok "--if-due exits successfully when healthy"
else
  no "--if-due exits successfully when healthy"
fi
check "--if-due leaves a healthy key unchanged" "$(key_of "$HOME_OK")" "$BEFORE_IF_DUE"
grep -q 'not due' "$HOME_OK/if-due-ok" || no "--if-due reports not due"

printf '\nage and exposure make --check due, and --if-due rotates\n'
RECEIPT="$HOME_OK/.local/state/dotfiles/mcpproxy/rotation.json"
OLD_EPOCH=$(( $(date +%s) - 100 * 86400 ))
tmp_receipt="$HOME_OK/receipt.tmp"
jq --argjson epoch "$OLD_EPOCH" '.updated_epoch = $epoch' "$RECEIPT" > "$tmp_receipt"
chmod 600 "$tmp_receipt"
mv "$tmp_receipt" "$RECEIPT"
if rotate "$HOME_OK" --check > "$HOME_OK/check-age" 2>&1; then
  no "aged key makes --check fail"
else
  ok "aged key makes --check fail"
fi
grep -q 'status due (age' "$HOME_OK/check-age" || no "aged check reports age reason"
AGED_KEY="$(key_of "$HOME_OK")"
if rotate "$HOME_OK" --if-due > "$HOME_OK/if-due-age" 2>&1; then
  ok "aged key rotates via --if-due"
else
  no "aged key rotates via --if-due"
  cat "$HOME_OK/if-due-age" >&2
fi
if [[ "$(key_of "$HOME_OK")" != "$AGED_KEY" ]]; then
  ok "aged --if-due changes the key"
else
  no "aged --if-due changes the key"
fi

HOME_EXPOSURE="$ROOT/exposure"
prepare_home "$HOME_EXPOSURE"
rotate "$HOME_EXPOSURE" > "$HOME_EXPOSURE/rotate" 2>&1 || no "exposure fixture rotation failed"
EXPOSURE_KEY="$(key_of "$HOME_EXPOSURE")"
mkdir -p "$HOME_EXPOSURE/.cache/dotfiles/logs"
chmod 700 "$HOME_EXPOSURE/.cache/dotfiles" "$HOME_EXPOSURE/.cache/dotfiles/logs"
printf 'leaked test material %s\n' "$EXPOSURE_KEY" > "$HOME_EXPOSURE/.cache/dotfiles/logs/test.log"
if rotate "$HOME_EXPOSURE" --check > "$HOME_EXPOSURE/check-exposure" 2>&1; then
  no "logged key makes --check fail"
else
  ok "logged key makes --check fail"
fi
grep -q 'exposure logs' "$HOME_EXPOSURE/check-exposure" || no "exposure check reports logs"
if rotate "$HOME_EXPOSURE" --if-due > "$HOME_EXPOSURE/if-due-exposure" 2>&1; then
  ok "exposed key rotates via --if-due"
else
  no "exposed key rotates via --if-due"
  cat "$HOME_EXPOSURE/if-due-exposure" >&2
fi
if [[ "$(key_of "$HOME_EXPOSURE")" != "$EXPOSURE_KEY" ]]; then
  ok "exposed --if-due changes the key"
else
  no "exposed --if-due changes the key"
fi
if rotate "$HOME_EXPOSURE" --check > "$HOME_EXPOSURE/check-after" 2>&1; then
  ok "old leaked key no longer marks the new key as exposed"
else
  no "old leaked key no longer marks the new key as exposed"
  cat "$HOME_EXPOSURE/check-after" >&2
fi

printf '\ninterrupted verification resumes without rotating again\n'
HOME_RESUME="$ROOT/resume"
prepare_home "$HOME_RESUME"
touch "$HOME_RESUME/fail-verify"
if rotate "$HOME_RESUME" > "$HOME_RESUME/first-output" 2>&1; then
  no "failed verification makes the first run fail"
else
  ok "failed verification makes the first run fail"
fi
RESUME_KEY="$(key_of "$HOME_RESUME")"
check "failed run leaves a resumable receipt" "$(phase_of "$HOME_RESUME")" clients-rendered
rm -f "$HOME_RESUME/fail-verify"
if rotate "$HOME_RESUME" > "$HOME_RESUME/resume-output" 2>&1; then
  ok "resumed run exits successfully"
else
  no "resumed run exits successfully"
  cat "$HOME_RESUME/resume-output" >&2
fi
check "resumed run keeps the same key" "$(key_of "$HOME_RESUME")" "$RESUME_KEY"
check "resumed run reaches verified" "$(phase_of "$HOME_RESUME")" verified
if grep -qF "$RESUME_KEY" "$HOME_RESUME/first-output" "$HOME_RESUME/resume-output"; then
  no "resumed key is absent from command output"
else
  ok "resumed key is absent from command output"
fi

printf '\nhelp does not need a config or lock\n'
HOME_HELP="$ROOT/help"
prepare_home "$HOME_HELP"
if rotate "$HOME_HELP" --help > "$HOME_HELP/help-output" 2>&1 &&
  grep -q 'Usage:' "$HOME_HELP/help-output"; then
  ok "--help prints usage without touching the config"
else
  no "--help prints usage without touching the config"
fi

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
