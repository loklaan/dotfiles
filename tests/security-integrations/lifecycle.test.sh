#!/usr/bin/env bash
# shellcheck disable=SC2016

#|----------------------------------------------------------------------------|
#| Paseo + Orca disablement regression tests                                  |
#|                                                                            |
#| Run: bash tests/security-integrations/lifecycle.test.sh                     |
#|                                                                            |
#| Every service command is a PATH-prepended fake. The harness never invokes  |
#| chezmoi apply/init or the host's service managers.                          |
#|----------------------------------------------------------------------------|

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(mktemp -d)"
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

prepare_home() {
  local home="$1"
  mkdir -p "$home/.local/lib" "$home/.config/chezmoi" "$home/shims" "$home/state"
  cp "$REPO/home/private_dot_local/lib/bash-logging.sh" "$home/.local/lib/"
  cp "$REPO/home/private_dot_local/lib/term-colour.sh" "$home/.local/lib/"
  cp "$REPO/home/private_dot_local/lib/pitchfork-lifecycle.sh" "$home/.local/lib/"
  cp "$REPO/home/private_dot_local/lib/desktop-app-lifecycle.sh" "$home/.local/lib/"

  make_fake "$home/shims/uname" 'printf "%s\\n" "${TEST_OS:-Linux}"'
  make_fake "$home/shims/sleep" 'exit 0'
  make_fake "$home/shims/curl" 'exit 1'
  make_fake "$home/shims/lsof" '
if [[ -f "$TEST_STATE/paseo-listener" ]]; then
  printf "paseo 1 user 1u IPv4 TCP *:6767 (LISTEN)\\n"
  exit 0
fi
exit 1'
  make_fake "$home/shims/pgrep" '
if [[ "${TEST_OS:-Linux}" == "Darwin" && -f "$TEST_STATE/${*: -1}-running" ]]; then exit 0; fi
exit 1'
  make_fake "$home/shims/systemctl" '
printf "systemctl %s\n" "$*" >> "$TEST_STATE/service.calls"
[[ "$1" == "--user" ]] && shift
action="$1"; shift
unit="${*: -1}"
case "$action" in
  cat|list-unit-files) exit 0 ;;
  is-active) [[ -f "$TEST_STATE/${unit}.active" ]] ;;
  is-enabled) [[ -f "$TEST_STATE/${unit}.enabled" ]] ;;
  stop)
    if [[ "${FAIL_SYSTEMCTL_STOP:-0}" == 1 ]]; then
      printf "user service manager rejected stop request\n" >&2
      exit 1
    fi
    rm -f "$TEST_STATE/${unit}.active" "$TEST_STATE/paseo-listener" ;;
  disable)
    if [[ "$unit" != orca-server.service || "${KEEP_LEGACY_ENABLED:-0}" != 1 ]]; then
      rm -f "$TEST_STATE/${unit}.enabled"
    fi
    if [[ " $* " == *" --now "* && ( "$unit" != orca-server.service || "${KEEP_LEGACY_ACTIVE:-0}" != 1 ) ]]; then
      rm -f "$TEST_STATE/${unit}.active"
    fi
    exit 0 ;;
  enable) touch "$TEST_STATE/${unit}.enabled" ;;
  start|restart) touch "$TEST_STATE/${unit}.active" "$TEST_STATE/paseo-listener" ;;
  daemon-reload) : ;;
esac'
  make_fake "$home/shims/pitchfork" '
printf "pitchfork %s\n" "$*" >> "$TEST_STATE/service.calls"
action="$1"; shift
case "$action" in
  stop)
    if [[ "${FAIL_PITCHFORK_STOP:-0}" == 1 ]]; then exit 1; fi
    rm -f "$TEST_STATE/$1.pitchfork" ;;
  start) touch "$TEST_STATE/${*: -1}.pitchfork" ;;
  list) for f in "$TEST_STATE"/*.pitchfork; do [[ -e "$f" ]] && basename "$f" .pitchfork; done ;;
  supervisor) : ;;
  boot) [[ "${1:-}" == status ]] && printf "pitchfork Boot start is enabled\\n" >&2 ;;
esac'
  make_fake "$home/shims/mise" '
if [[ "$1" == which && "$2" == pitchfork ]]; then printf "%s/shims/pitchfork\\n" "$HOME"; exit 0; fi
if [[ "$1" == which && "$2" == orca ]]; then printf "%s/shims/orca\\n" "$HOME"; exit 0; fi
exit 0'
  make_fake "$home/shims/launchctl" 'printf "launchctl %s\\n" "$*" >> "$TEST_STATE/macos.calls"'
  make_fake "$home/shims/osascript" '
printf "osascript %s\\n" "$*" >> "$TEST_STATE/macos.calls"
[[ "$*" == *Paseo*"to quit"* ]] && rm -f "$TEST_STATE/Paseo-running"
[[ "$*" == *Orca*"to quit"* ]] && rm -f "$TEST_STATE/Orca-running"
exit 0'
  make_fake "$home/shims/plutil" 'printf "com.example.%s\\n" "${*: -1}"'
  make_fake "$home/shims/orca" 'exit 0'
  make_fake "$home/shims/paseo" 'exit 0'
}

write_config() {
  local home="$1" paseo="$2" orca="$3"
  cat > "$home/.config/chezmoi/chezmoi.toml" <<EOF
[data]
paseoDaemon = $paseo
orcaServer = $orca
unrelated = "preserved"
EOF
}

render_script() {
  local os="$1" source="$2" output="$3" paseo="$4" orca="$5"
  chezmoi execute-template -S "$REPO/home" \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"},\"paseoDaemon\":$paseo,\"orcaServer\":$orca}" \
    --file "$source" > "$output"
  chmod 755 "$output"
}

run_linux_cycle() {
  local home="$1" rendered_paseo="$2" rendered_orca="$3"
  env HOME="$home" TEST_STATE="$home/state" PATH="$home/shims:$PATH" \
    bash "$REPO/home/.chezmoiscripts/run_once_after_install-054-disable-paseo-orca.sh" || return
  env HOME="$home" TEST_STATE="$home/state" PATH="$home/shims:$PATH" bash "$rendered_paseo" || return
  env HOME="$home" TEST_STATE="$home/state" PATH="$home/shims:$PATH" bash "$rendered_orca"
}

printf '\nstale cached true -> disabled\n'
HOME_TRUE="$ROOT/true"
prepare_home "$HOME_TRUE"
write_config "$HOME_TRUE" true true
touch "$HOME_TRUE/state/paseo-daemon.service.active" "$HOME_TRUE/state/paseo-daemon.service.enabled"
touch "$HOME_TRUE/state/paseo-listener" "$HOME_TRUE/state/df-orca-server.pitchfork"
render_script linux "$REPO/home/.chezmoiscripts/run_after_install-057-paseo-daemon.sh.tmpl" "$HOME_TRUE/paseo.sh" true true
render_script linux "$REPO/home/.chezmoiscripts/run_after_install-059-orca-server.sh.tmpl" "$HOME_TRUE/orca.sh" true true
if run_linux_cycle "$HOME_TRUE" "$HOME_TRUE/paseo.sh" "$HOME_TRUE/orca.sh" >"$HOME_TRUE/output" 2>&1; then
  check "migrates paseoDaemon to false" "$(yq -p=toml -o=json -r '.data.paseoDaemon' "$HOME_TRUE/.config/chezmoi/chezmoi.toml")" false
  check "migrates orcaServer to false" "$(yq -p=toml -o=json -r '.data.orcaServer' "$HOME_TRUE/.config/chezmoi/chezmoi.toml")" false
  check "preserves unrelated TOML data" "$(yq -p=toml -o=json -r '.data.unrelated' "$HOME_TRUE/.config/chezmoi/chezmoi.toml")" preserved
  check "stops paseo and its listener" "$([[ ! -e "$HOME_TRUE/state/paseo-daemon.service.active" && ! -e "$HOME_TRUE/state/paseo-listener" ]] && echo stopped)" stopped
  check "disables paseo" "$([[ ! -e "$HOME_TRUE/state/paseo-daemon.service.enabled" ]] && echo disabled)" disabled
  check "stops orca Pitchfork daemon" "$([[ ! -e "$HOME_TRUE/state/df-orca-server.pitchfork" ]] && echo stopped)" stopped
else
  no "cached true fixture converges: $(tr '\n' ';' < "$HOME_TRUE/output")"
fi

printf '\nfuture explicit true -> retained opt-in starts\n'
write_config "$HOME_TRUE" true true
env HOME="$HOME_TRUE" TEST_STATE="$HOME_TRUE/state" PATH="$HOME_TRUE/shims:$PATH" bash "$HOME_TRUE/paseo.sh" >/dev/null 2>&1
env HOME="$HOME_TRUE" TEST_STATE="$HOME_TRUE/state" PATH="$HOME_TRUE/shims:$PATH" bash "$HOME_TRUE/orca.sh" >/dev/null 2>&1
check "future true enables and starts paseo" "$([[ -e "$HOME_TRUE/state/paseo-daemon.service.active" && -e "$HOME_TRUE/state/paseo-daemon.service.enabled" ]] && echo started)" started
check "future true starts orca Pitchfork daemon" "$([[ -e "$HOME_TRUE/state/df-orca-server.pitchfork" ]] && echo started)" started

printf '\nrepeated cached false -> remains disabled\n'
HOME_FALSE="$ROOT/false"
prepare_home "$HOME_FALSE"
write_config "$HOME_FALSE" false false
render_script linux "$REPO/home/.chezmoiscripts/run_after_install-057-paseo-daemon.sh.tmpl" "$HOME_FALSE/paseo.sh" false false
render_script linux "$REPO/home/.chezmoiscripts/run_after_install-059-orca-server.sh.tmpl" "$HOME_FALSE/orca.sh" false false
if run_linux_cycle "$HOME_FALSE" "$HOME_FALSE/paseo.sh" "$HOME_FALSE/orca.sh" >/dev/null 2>&1 && \
   env HOME="$HOME_FALSE" TEST_STATE="$HOME_FALSE/state" PATH="$HOME_FALSE/shims:$PATH" bash "$HOME_FALSE/paseo.sh" >/dev/null 2>&1 && \
   env HOME="$HOME_FALSE" TEST_STATE="$HOME_FALSE/state" PATH="$HOME_FALSE/shims:$PATH" bash "$HOME_FALSE/orca.sh" >/dev/null 2>&1; then
  ok "repeated false lifecycle remains successful and stopped"
else
  no "repeated false lifecycle remains successful and stopped"
fi

printf '\nfailed stop -> visible non-success\n'
HOME_FAIL="$ROOT/fail"
prepare_home "$HOME_FAIL"
write_config "$HOME_FAIL" false false
touch "$HOME_FAIL/state/paseo-daemon.service.active" "$HOME_FAIL/state/paseo-listener"
render_script linux "$REPO/home/.chezmoiscripts/run_after_install-057-paseo-daemon.sh.tmpl" "$HOME_FAIL/paseo.sh" false false
if env HOME="$HOME_FAIL" TEST_STATE="$HOME_FAIL/state" FAIL_SYSTEMCTL_STOP=1 PATH="$HOME_FAIL/shims:$PATH" \
  bash "$HOME_FAIL/paseo.sh" >"$HOME_FAIL/output" 2>&1; then
  no "failed systemctl stop returns non-success"
else
  ok "failed systemctl stop returns non-success"
fi
if grep -q 'warning.*systemctl could not stop paseo-daemon.service: user service manager rejected stop request' "$HOME_FAIL/output"; then
  ok "failed systemctl stop preserves safe stderr"
else
  no "failed systemctl stop preserves safe stderr"
fi

printf '\nshared pf_stop contract -> unrelated failure remains best-effort\n'
HOME_SHARED="$ROOT/shared"
prepare_home "$HOME_SHARED"
if env HOME="$HOME_SHARED" TEST_STATE="$HOME_SHARED/state" FAIL_PITCHFORK_STOP=1 PATH="$HOME_SHARED/shims:$PATH" \
  bash -c 'source "$HOME/.local/lib/pitchfork-lifecycle.sh"; PITCHFORK_BIN="$HOME/shims/pitchfork"; pf_stop df-mcpproxy'; then
  ok "failed unrelated pf_stop still returns success"
else
  no "failed unrelated pf_stop still returns success"
fi

printf '\nfailed Orca stop -> local verification reports non-success\n'
HOME_ORCA_FAIL="$ROOT/orca-fail"
prepare_home "$HOME_ORCA_FAIL"
write_config "$HOME_ORCA_FAIL" false false
touch "$HOME_ORCA_FAIL/state/df-orca-server.pitchfork"
render_script linux "$REPO/home/.chezmoiscripts/run_after_install-059-orca-server.sh.tmpl" "$HOME_ORCA_FAIL/orca.sh" false false
if env HOME="$HOME_ORCA_FAIL" TEST_STATE="$HOME_ORCA_FAIL/state" FAIL_PITCHFORK_STOP=1 PATH="$HOME_ORCA_FAIL/shims:$PATH" \
  bash "$HOME_ORCA_FAIL/orca.sh" >"$HOME_ORCA_FAIL/output" 2>&1; then
  no "Orca opt-out detects a still-running Pitchfork daemon"
else
  ok "Orca opt-out detects a still-running Pitchfork daemon"
fi
if grep -q 'warning.*Pitchfork still reports df-orca-server running after the stop request' "$HOME_ORCA_FAIL/output"; then
  ok "Orca opt-out emits its own failed-stop warning"
else
  no "Orca opt-out emits its own failed-stop warning"
fi

printf '\nconfig diagnostics -> missing tool and missing file remain distinct\n'
HOME_DIAG="$ROOT/diagnostics"
prepare_home "$HOME_DIAG"
render_script linux "$REPO/home/.chezmoiscripts/run_after_install-057-paseo-daemon.sh.tmpl" "$HOME_DIAG/paseo.sh" false false
render_script linux "$REPO/home/.chezmoiscripts/run_after_install-059-orca-server.sh.tmpl" "$HOME_DIAG/orca.sh" false false
env HOME="$HOME_DIAG" TEST_STATE="$HOME_DIAG/state" PATH="$HOME_DIAG/shims:$PATH" \
  bash "$HOME_DIAG/paseo.sh" >"$HOME_DIAG/missing-config.output" 2>&1 || true
if grep -q "warning.*Treating paseoDaemon as disabled because ${HOME_DIAG}/.config/chezmoi/chezmoi.toml does not exist" "$HOME_DIAG/missing-config.output"; then
  ok "missing config names the absent file"
else
  no "missing config names the absent file"
fi
write_config "$HOME_DIAG" false false
cat > "$HOME_DIAG/hide-yq.bash" <<'EOF'
command() {
  if [[ "${HIDE_YQ:-0}" == 1 && "${1:-}" == -v && "${2:-}" == yq ]]; then
    return 1
  fi
  builtin command "$@"
}
EOF
env HOME="$HOME_DIAG" TEST_STATE="$HOME_DIAG/state" HIDE_YQ=1 BASH_ENV="$HOME_DIAG/hide-yq.bash" PATH="$HOME_DIAG/shims:$PATH" \
  bash "$HOME_DIAG/orca.sh" >"$HOME_DIAG/missing-yq.output" 2>&1 || true
if grep -q 'warning.*Treating orcaServer as disabled because yq is not on PATH' "$HOME_DIAG/missing-yq.output" && \
   ! grep -q 'does not exist' "$HOME_DIAG/missing-yq.output"; then
  ok "missing yq names only the missing tool"
else
  no "missing yq names only the missing tool"
fi

printf '\nmalformed config -> lifecycle aborts before service commands\n'
cat > "$HOME_DIAG/.config/chezmoi/chezmoi.toml" <<'EOF'
[data]
privateToken = "do-not-log-this-value"
malformed = [
EOF
cp "$HOME_DIAG/.config/chezmoi/chezmoi.toml" "$HOME_DIAG/malformed.before"
rm -f "$HOME_DIAG/state/service.calls"
if env HOME="$HOME_DIAG" TEST_STATE="$HOME_DIAG/state" PATH="$HOME_DIAG/shims:$PATH" \
  bash "$HOME_DIAG/paseo.sh" >"$HOME_DIAG/paseo-parse.output" 2>&1; then
  no "malformed config aborts Paseo lifecycle"
else
  ok "malformed config aborts Paseo lifecycle"
fi
if grep -q 'warning.*Paseo lifecycle aborted because yq could not read data.paseoDaemon' "$HOME_DIAG/paseo-parse.output" && \
   ! grep -q 'do-not-log-this-value' "$HOME_DIAG/paseo-parse.output"; then
  ok "Paseo parse failure is specific and suppresses config contents"
else
  no "Paseo parse failure is specific and suppresses config contents"
fi
check "Paseo parse failure leaves config unchanged" "$(cmp -s "$HOME_DIAG/malformed.before" "$HOME_DIAG/.config/chezmoi/chezmoi.toml" && echo unchanged)" unchanged
check "Paseo parse failure runs no service commands" "$([[ ! -e "$HOME_DIAG/state/service.calls" ]] && echo none)" none

rm -f "$HOME_DIAG/state/service.calls"
if env HOME="$HOME_DIAG" TEST_STATE="$HOME_DIAG/state" PATH="$HOME_DIAG/shims:$PATH" \
  bash "$HOME_DIAG/orca.sh" >"$HOME_DIAG/orca-parse.output" 2>&1; then
  no "malformed config aborts Orca lifecycle"
else
  ok "malformed config aborts Orca lifecycle"
fi
if grep -q 'warning.*Orca lifecycle aborted because yq could not read data.orcaServer' "$HOME_DIAG/orca-parse.output" && \
   ! grep -q 'do-not-log-this-value' "$HOME_DIAG/orca-parse.output"; then
  ok "Orca parse failure is specific and suppresses config contents"
else
  no "Orca parse failure is specific and suppresses config contents"
fi
check "Orca parse failure leaves config unchanged" "$(cmp -s "$HOME_DIAG/malformed.before" "$HOME_DIAG/.config/chezmoi/chezmoi.toml" && echo unchanged)" unchanged
check "Orca parse failure runs no service commands" "$([[ ! -e "$HOME_DIAG/state/service.calls" ]] && echo none)" none

write_config "$HOME_DIAG" false false

printf '\nlegacy Orca unit -> active and enabled residue diagnosed separately\n'
touch "$HOME_DIAG/state/orca-server.service.active" "$HOME_DIAG/state/orca-server.service.enabled"
if env HOME="$HOME_DIAG" TEST_STATE="$HOME_DIAG/state" KEEP_LEGACY_ACTIVE=1 KEEP_LEGACY_ENABLED=1 PATH="$HOME_DIAG/shims:$PATH" \
  bash "$HOME_DIAG/orca.sh" >"$HOME_DIAG/legacy-residue.output" 2>&1; then
  no "legacy unit residue returns non-success"
else
  ok "legacy unit residue returns non-success"
fi
if grep -q 'warning.*Legacy orca-server.service remains active after systemctl reported successful retirement' "$HOME_DIAG/legacy-residue.output"; then
  ok "legacy active residue has a single-cause warning"
else
  no "legacy active residue has a single-cause warning"
fi
if grep -q 'warning.*Legacy orca-server.service remains enabled after systemctl reported successful retirement' "$HOME_DIAG/legacy-residue.output"; then
  ok "legacy enabled residue has a single-cause warning"
else
  no "legacy enabled residue has a single-cause warning"
fi

printf '\nmacOS desktop apps -> quit and auto-launch disabled\n'
HOME_MAC="$ROOT/mac"
prepare_home "$HOME_MAC"
write_config "$HOME_MAC" false false
touch "$HOME_MAC/state/Paseo-running" "$HOME_MAC/state/Orca-running"
mkdir -p "$HOME_MAC/Library/LaunchAgents"
touch "$HOME_MAC/Library/LaunchAgents/com.example.paseo.plist" "$HOME_MAC/Library/LaunchAgents/com.example.orca.plist"
render_script darwin "$REPO/home/.chezmoiscripts/run_after_install-057-paseo-daemon.sh.tmpl" "$HOME_MAC/paseo.sh" false false
render_script darwin "$REPO/home/.chezmoiscripts/run_after_install-059-orca-server.sh.tmpl" "$HOME_MAC/orca.sh" false false
env HOME="$HOME_MAC" TEST_OS=Darwin TEST_STATE="$HOME_MAC/state" PATH="$HOME_MAC/shims:$PATH" bash "$HOME_MAC/paseo.sh" >"$HOME_MAC/paseo.output" 2>&1 || no "Paseo macOS lifecycle succeeds: $(tr '\n' ';' < "$HOME_MAC/paseo.output")"
env HOME="$HOME_MAC" TEST_OS=Darwin TEST_STATE="$HOME_MAC/state" PATH="$HOME_MAC/shims:$PATH" bash "$HOME_MAC/orca.sh" >"$HOME_MAC/orca.output" 2>&1 || no "Orca macOS lifecycle succeeds: $(tr '\n' ';' < "$HOME_MAC/orca.output")"
check "quits both running desktop apps" "$(grep -c 'tell application .* to quit' "$HOME_MAC/state/macos.calls" 2>/dev/null || true)" 2
check "disables both LaunchAgents" "$(grep -c '^launchctl disable ' "$HOME_MAC/state/macos.calls" 2>/dev/null || true)" 2
check "removes both login items" "$(grep -c 'delete every login item' "$HOME_MAC/state/macos.calls" 2>/dev/null || true)" 2

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
