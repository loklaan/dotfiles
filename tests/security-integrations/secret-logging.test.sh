#!/usr/bin/env bash
# shellcheck disable=SC2016

#|----------------------------------------------------------------------------|
#| Secret logging regression tests                                            |
#|                                                                            |
#| Run: bash tests/security-integrations/secret-logging.test.sh                |
#|                                                                            |
#| The harness renders templates and uses isolated HOME/PATH fixtures. It      |
#| never invokes chezmoi apply/init or truncates PATH.                         |
#|----------------------------------------------------------------------------|

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(mktemp -d)"
REAL_STAT="$(command -v stat)"
PASS=0
FAIL=0
FAKE_TOKEN="security-regression-token-value"
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

prepare_home() {
  local home="$1"
  mkdir -p "$home/.local/lib" "$home/.cache/dotfiles/logs" "$home/shims"
  chmod 700 "$home/.cache/dotfiles" "$home/.cache/dotfiles/logs"
  cp "$REPO/home/private_dot_local/lib/bash-logging.sh" "$home/.local/lib/"
  cp "$REPO/home/private_dot_local/lib/term-colour.sh" "$home/.local/lib/"
}

render_github_token() {
  local profile="$1" output="$2"
  chezmoi execute-template -S "$REPO/home" \
    --override-data "{\"machineProfile\":\"$profile\"}" \
    --file "$REPO/home/private_dot_local/bin/executable_github-token.tmpl" > "$output"
  chmod 755 "$output"
}

extract_hook() {
  local section="$1" output="$2"
  awk -v section="[$section]" '
    $0 == section { in_section = 1; next }
    in_section && /args = .*'"'"''"'"''"'"'$/ { in_body = 1; next }
    in_body && /^'"'"''"'"''"'"'\]/ { exit }
    in_body { print }
  ' "$REPO/home/.chezmoi.toml.tmpl" > "$output"
  chmod 755 "$output"
}

file_mode() {
  if [[ "$(uname -s)" == Darwin ]]; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

wait_for_log_text() {
  local path="$1" text="$2"
  local _
  for _ in {1..50}; do
    grep -qF "$text" "$path" 2>/dev/null && return 0
    sleep 0.02
  done
  return 1
}

logs_contain_token() {
  local home="$1"
  local log
  local nullglob_was_set=0
  shopt -q nullglob && nullglob_was_set=1
  shopt -s nullglob
  for log in "$home"/.cache/dotfiles/logs/*.log*; do
    if grep -qF "$FAKE_TOKEN" "$log"; then
      [[ "$nullglob_was_set" -eq 1 ]] || shopt -u nullglob
      return 0
    fi
  done
  [[ "$nullglob_was_set" -eq 1 ]] || shopt -u nullglob
  return 1
}

run_github_token_case() {
  local profile="$1" debug="$2"
  local home="$ROOT/github-${profile}-${debug}"
  local session_log output
  prepare_home "$home"
  render_github_token "$profile" "$home/github-token"
  session_log="$home/.cache/dotfiles/logs/chezmoi-session.fixture.log"
  : > "$session_log"
  chmod 600 "$session_log"
  printf '%s\n' "$session_log" > "$home/.cache/dotfiles/chezmoi-session-current"
  chmod 600 "$home/.cache/dotfiles/chezmoi-session-current"

  if [[ "$profile" == work ]]; then
    make_fake "$home/shims/git" 'printf "protocol=https\nhost=github.com\npassword=%s\n" "$FAKE_TOKEN"'
    output=$(env HOME="$home" DEBUG="$debug" FAKE_TOKEN="$FAKE_TOKEN" PATH="$home/shims:$PATH" "$home/github-token")
  else
    output=$(env HOME="$home" DEBUG="$debug" GITHUB_TOKEN="$FAKE_TOKEN" "$home/github-token")
  fi

  check "$profile profile with DEBUG=$debug returns only the token" "$output" "$FAKE_TOKEN"
  if logs_contain_token "$home"; then
    no "$profile profile with DEBUG=$debug keeps token out of logs"
  else
    ok "$profile profile with DEBUG=$debug keeps token out of logs"
  fi
}

printf '\ngithub-token output is never session-logged\n'
run_github_token_case personal 0
run_github_token_case personal 1
run_github_token_case work 0
run_github_token_case work 1
if env HOME="$ROOT/github-personal-0" "$ROOT/github-personal-0/github-token" --help | grep -q 'Usage:'; then
  ok "github-token help works without session logging setup"
else
  no "github-token help failed without session logging setup"
fi

printf '\nstandalone logging uses private modes\n'
HOME_STANDALONE="$ROOT/standalone"
prepare_home "$HOME_STANDALONE"
cat > "$HOME_STANDALONE/log-event" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "${HOME}/.local/lib/bash-logging.sh"
setup_session_logging "standalone-fixture"
printf 'standalone-event\n'
EOF
chmod 755 "$HOME_STANDALONE/log-event"
env HOME="$HOME_STANDALONE" "$HOME_STANDALONE/log-event" >/dev/null
STANDALONE_LOG=("$HOME_STANDALONE"/.cache/dotfiles/logs/standalone-fixture.*.log.*)
check "standalone log directory is 0700" "$(file_mode "$HOME_STANDALONE/.cache/dotfiles/logs")" 700
check "standalone log file is 0600" "$(file_mode "${STANDALONE_LOG[0]}")" 600
if wait_for_log_text "${STANDALONE_LOG[0]}" standalone-event; then
  ok "standalone logging records output"
else
  no "standalone logging did not record output"
fi

printf '\nmismatched uname and stat userlands\n'
HOME_MISMATCH="$ROOT/uname-mismatch"
prepare_home "$HOME_MISMATCH"
make_fake "$HOME_MISMATCH/shims/uname" 'printf "Linux\n"'
MISMATCH_UID=$(env HOME="$HOME_MISMATCH" PATH="$HOME_MISMATCH/shims:$PATH" bash -c '
source "$HOME/.local/lib/bash-logging.sh"
_bl_prepare_private_directory "$HOME/.cache/dotfiles/mismatch"
_bl_path_uid "$HOME/.cache/dotfiles/mismatch"')
check "uid lookup follows stat capability when uname disagrees" "$MISMATCH_UID" "$(id -u)"

printf '\nsymlinked and foreign-owned marker state is rejected\n'
HOME_SYMLINK="$ROOT/symlink-marker"
prepare_home "$HOME_SYMLINK"
HOSTILE_LOG="$ROOT/hostile-symlink.log"
: > "$HOSTILE_LOG"
printf '%s\n' "$HOSTILE_LOG" > "$ROOT/marker-target"
ln -s "$ROOT/marker-target" "$HOME_SYMLINK/.cache/dotfiles/chezmoi-session-current"
env HOME="$HOME_SYMLINK" bash "$HOME_STANDALONE/log-event" >"$HOME_SYMLINK/output" 2>&1
if grep -q 'Logging file rejected: symbolic links' "$HOME_SYMLINK/output"; then
  ok "symlinked marker reports the specific rejection reason"
else
  no "symlinked marker reports the specific rejection reason"
fi
if [[ ! -s "$HOSTILE_LOG" ]]; then
  ok "symlinked marker is rejected"
else
  no "symlinked marker redirected logging"
fi
SYMLINK_FALLBACK=("$HOME_SYMLINK"/.cache/dotfiles/logs/standalone-fixture.*.log.*)
if wait_for_log_text "${SYMLINK_FALLBACK[0]}" standalone-event; then
  ok "symlinked marker falls back to private standalone logging"
else
  no "symlinked marker did not fall back to standalone logging"
fi

HOME_FOREIGN="$ROOT/foreign-target"
prepare_home "$HOME_FOREIGN"
FOREIGN_LOG="$HOME_FOREIGN/.cache/dotfiles/logs/foreign.log"
: > "$FOREIGN_LOG"
chmod 600 "$FOREIGN_LOG"
printf '%s\n' "$FOREIGN_LOG" > "$HOME_FOREIGN/.cache/dotfiles/chezmoi-session-current"
chmod 600 "$HOME_FOREIGN/.cache/dotfiles/chezmoi-session-current"
make_fake "$HOME_FOREIGN/shims/stat" '
target="${*: -1}"
if [[ "$target" == "$TEST_FOREIGN_PATH" ]]; then
  printf "%s\n" "$(( $(id -u) + 1 ))"
else
  exec "$TEST_REAL_STAT" "$@"
fi'
env HOME="$HOME_FOREIGN" TEST_FOREIGN_PATH="$FOREIGN_LOG" TEST_REAL_STAT="$REAL_STAT" \
  PATH="$HOME_FOREIGN/shims:$PATH" bash "$HOME_STANDALONE/log-event" >"$HOME_FOREIGN/output" 2>&1
if grep -q 'Logging file rejected: owner UID' "$HOME_FOREIGN/output"; then
  ok "foreign-owned log reports an ownership rejection"
else
  no "foreign-owned log reports an ownership rejection"
fi
if [[ ! -s "$FOREIGN_LOG" ]]; then
  ok "foreign-owned log target is rejected"
else
  no "foreign-owned log target received output"
fi
FOREIGN_FALLBACK=("$HOME_FOREIGN"/.cache/dotfiles/logs/standalone-fixture.*.log.*)
if wait_for_log_text "${FOREIGN_FALLBACK[0]}" standalone-event; then
  ok "foreign-owned target falls back to private standalone logging"
else
  no "foreign-owned target did not fall back to standalone logging"
fi

printf '\napply and update hooks share private session logging\n'
for operation in apply update; do
  home="$ROOT/hook-$operation"
  prepare_home "$home"
  extract_hook "hooks.$operation.pre" "$home/pre-hook"
  extract_hook "hooks.$operation.post" "$home/post-hook"
  env HOME="$home" bash -euo pipefail "$home/pre-hook" >/dev/null
  marker="$home/.cache/dotfiles/chezmoi-session-current"
  hook_log=$(<"$marker")
  check "$operation hook log directory is 0700" "$(file_mode "$home/.cache/dotfiles/logs")" 700
  check "$operation hook marker is 0600" "$(file_mode "$marker")" 600
  check "$operation hook log is 0600" "$(file_mode "$hook_log")" 600
  env HOME="$home" bash "$HOME_STANDALONE/log-event" >/dev/null
  if wait_for_log_text "$hook_log" standalone-event; then
    ok "$operation hook marker routes callers to the session log"
  else
    no "$operation hook marker did not route logging"
  fi
  env HOME="$home" bash -euo pipefail "$home/post-hook"
  if [[ ! -e "$marker" && ! -L "$marker" ]]; then
    ok "$operation post-hook removes the marker"
  else
    no "$operation post-hook left its marker"
  fi
done

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
