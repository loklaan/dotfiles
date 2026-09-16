#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG="${ROOT}/home/.chezmoi.toml.tmpl"
INSTALL="${ROOT}/install.sh"
LIFECYCLE="${ROOT}/home/.chezmoiscripts/run_after_install-049-ephemeral-cache.sh.tmpl"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local expected=$2
  grep -Fq -- "$expected" "$file" || fail "${file} does not contain: ${expected}"
}

assert_not_exists() {
  local path=$1
  [ ! -e "$path" ] || fail "unexpected path exists: ${path}"
}

assert_contains "$CONFIG" '{{- $ephemeralCache := promptBoolOnce . "ephemeralCache" "Use ephemeral storage for ~/.cache on this machine?" false -}}'
assert_contains "$CONFIG" 'ephemeralCache = {{ $ephemeralCache }}'
assert_contains "$INSTALL" 'config_ephemeral_cache="$(chezmoi execute-template "{{ dig \"ephemeralCache\" false . }}" 2>/dev/null || echo "false")"'
assert_contains "$INSTALL" '--promptBool="Use ephemeral storage for ~/.cache on this machine?=${config_ephemeral_cache}"'

[ -f "$LIFECYCLE" ] || fail "missing lifecycle script: ${LIFECYCLE}"
assert_contains "$LIFECYCLE" '{{- if and (eq .chezmoi.os "linux") (eq (dig "machineProfile" "personal" .) "work") (dig "ephemeralCache" false .) -}}'
assert_contains "$LIFECYCLE" 'if [ -z "${CODER:-}" ]; then'
assert_contains "$LIFECYCLE" 'touch "${HOME}/.use-ephemeral-cache"'
assert_contains "$LIFECYCLE" 'sudo -n systemctl restart configure-ephemeral-storage'

rendered=$(mktemp)
test_root=$(mktemp -d)
cleanup() {
  rm -f "$rendered"
  rm -rf "$test_root"
}
trap cleanup EXIT

sed '1d;$d' "$LIFECYCLE" > "$rendered"
bash -n "$rendered"

mkdir -p "$test_root/home/.local/lib" "$test_root/bin"
cp "$ROOT/home/private_dot_local/lib/bash-logging.sh" "$test_root/home/.local/lib/bash-logging.sh"

cat > "$test_root/bin/sudo" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$EPHEMERAL_CACHE_TEST_CALLS"
rm -rf -- "$HOME/.cache"
ln -s "/mnt/ephemeral${HOME}/.cache" "$HOME/.cache"
SHIM
cat > "$test_root/bin/systemctl" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
chmod +x "$test_root/bin/sudo" "$test_root/bin/systemctl"

calls="$test_root/calls"
HOME="$test_root/home" USER=coder CODER=true EPHEMERAL_CACHE_TEST_CALLS="$calls" \
  PATH="$test_root/bin:$PATH" bash "$rendered"

[ -f "$test_root/home/.use-ephemeral-cache" ] || fail "enabled Coder run did not create marker"
[ -L "$test_root/home/.cache" ] || fail "enabled Coder run did not produce cache symlink"
assert_contains "$calls" '-n systemctl restart configure-ephemeral-storage'

rm -f "$calls"
rm -f "$test_root/home/.use-ephemeral-cache" "$test_root/home/.cache"
mkdir -p "$test_root/home/.cache"

HOME="$test_root/home" USER=coder EPHEMERAL_CACHE_TEST_CALLS="$calls" \
  PATH="$test_root/bin:$PATH" bash "$rendered"

assert_not_exists "$test_root/home/.use-ephemeral-cache"
assert_not_exists "$calls"

printf 'PASS: ephemeral cache config and lifecycle contract\n'
