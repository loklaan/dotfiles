#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Guards run_after_install-072-opencode-tui-plugins. Its template must render
# empty once node_modules was installed from the source package.json and
# bun.lock, and render again when the install stamp is stale or node_modules
# is gone. The script must fall back to the Bun built into opencode when no
# standalone bun runs, and only warn when neither runs. Between those cases it
# runs the shared /changes core's behaviour tests against the installed
# effect, the copy OpenCode 1 loads.
#
# Installs into a temporary home through Bun's cache, so a cold cache needs
# network. Skips when opencode is not on PATH.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="${ROOT}/home/.chezmoiscripts/run_after_install-072-opencode-tui-plugins.sh.tmpl"
PACKAGE="${ROOT}/home/private_dot_local/share/dotfiles/opencode-tui-plugins"
CORE_TESTS="${ROOT}/tests/opencode-tui-plugins/changes.test.ts"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

if ! command -v opencode >/dev/null 2>&1; then
  printf 'SKIP: opencode is not on PATH\n'
  exit 0
fi

test_root=$(mktemp -d)
cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

store="${test_root}/.local/share/dotfiles/opencode-tui-plugins"
stamp="${store}/node_modules/.dotfiles-install.sha256"
data="${test_root}/data.json"
rendered="${test_root}/072.sh"
mkdir -p "$store" "${test_root}/no-bun" "${test_root}/no-runtime"
cp -R "${PACKAGE}/." "${store}/"
jq -n --arg home "$test_root" '{chezmoi: {homeDir: $home}}' > "$data"

# Shims that fail the way a mise shim does for a tool that is not installed.
printf '#!/bin/sh\nexit 127\n' > "${test_root}/no-bun/bun"
cp "${test_root}/no-bun/bun" "${test_root}/no-runtime/bun"
cp "${test_root}/no-bun/bun" "${test_root}/no-runtime/opencode"
chmod +x "${test_root}/no-bun/bun" "${test_root}/no-runtime/bun" "${test_root}/no-runtime/opencode"

render() {
  chezmoi execute-template -S "$ROOT" --override-data-file "$data" -f "$SCRIPT" > "$rendered"
}

# chezmoi skips a script that renders to whitespace only, so test for that.
renders_script() {
  [ -n "$(tr -d '[:space:]' < "$rendered")" ]
}

# run_script [shim dir]: runs the rendered script with the shims first on
# PATH. The logging variables make it log as a nested session, so it never
# appends to a real chezmoi session log.
run_script() {
  local shims=${1:-}
  PATH="${shims:+${shims}:}${PATH}" BASH_LOGGING_ACTIVE=1 \
    BASH_LOGGING_FILE="${test_root}/session.log" "$BASH" "$rendered" 2>&1
}

render
renders_script || fail "renders empty before anything is installed"
output=$(run_script) || fail "install exited non-zero: ${output}"
version=$(jq -r .version "${store}/node_modules/effect/package.json" 2>/dev/null || true)
[ "$version" = "4.0.0" ] || fail "installed effect '${version}', expected 4.0.0: ${output}"
[ -s "$stamp" ] || fail "wrote no install stamp: ${output}"

render
! renders_script || fail "renders after an install from the current lockfile"

printf 'stale\n' > "$stamp"
render
renders_script || fail "renders empty with a stale install stamp"

bun=(bun)
bun --version >/dev/null 2>&1 || bun=(env BUN_BE_BUN=1 opencode)
cp "$CORE_TESTS" "${store}/changed-files/"
(cd "${store}/changed-files" && "${bun[@]}" test ./changes.test.ts) ||
  fail "the /changes core behaviour tests failed"
rm "${store}/changed-files/changes.test.ts"

rm -rf "${store}/node_modules"
render
renders_script || fail "renders empty after node_modules was deleted"
output=$(run_script "${test_root}/no-bun") || fail "fallback install exited non-zero: ${output}"
case "$output" in
  *"built into opencode"*) ;;
  *) fail "did not fall back to the Bun built into opencode: ${output}" ;;
esac
[ -s "$stamp" ] || fail "fallback install wrote no install stamp: ${output}"

rm -rf "${store}/node_modules"
render
output=$(run_script "${test_root}/no-runtime") ||
  fail "exited non-zero without a Bun runtime: ${output}"
case "$output" in
  *"neither bun nor opencode can run Bun"*) ;;
  *) fail "did not warn without a Bun runtime: ${output}" ;;
esac
[ ! -e "$stamp" ] || fail "wrote an install stamp without installing"

printf 'PASS: opencode TUI plugin install guard and /changes core\n'
