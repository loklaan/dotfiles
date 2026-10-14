#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHEZMOI=$(command -v chezmoi)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
TEST_HOME="${TEST_ROOT}/home"
BIN="${TEST_ROOT}/bin"
CALLS="${TEST_ROOT}/calls"
export CALLS

mkdir -p "$BIN" "$TEST_HOME/.local/lib" "$TEST_HOME/.local/bin" \
  "$TEST_HOME/.local/share/opencode2/bin"
printf '{}\n' > "$TEST_ROOT/config.json"
cp "$ROOT/home/private_dot_local/lib/"{bash-logging,pitchfork-lifecycle}.sh \
  "$TEST_HOME/.local/lib/"

cat > "$BIN/pitchfork" <<'SH'
#!/bin/sh
echo "pitchfork $*" >> "$CALLS"
case "$*" in
  list) echo df-skulk ;;
  "boot status") echo 'Boot start is enabled' >&2 ;;
  "start --quiet df-skulk") exit "${START_RC:-0}" ;;
esac
SH
cat > "$BIN/mise" <<'SH'
#!/bin/sh
echo "mise $*" >> "$CALLS"
case "$1" in
  which)
    [ "$2" != "${MISSING_TOOL:-}" ] || exit 1
    command -v "$2"
    ;;
  exec)
    if [ "${HEALTH_STOPPED:-0}" = 1 ]; then
      echo 'Daemon NOT running.'
    else
      echo 'Daemon running (pid 123).'
    fi
    exit "${HEALTH_RC:-0}"
    ;;
esac
SH
printf '#!/bin/sh\nexit 0\n' | tee "$BIN/bun" "$BIN/skulk" "$BIN/sleep" \
  "$TEST_HOME/.local/bin/opencode2" "$TEST_HOME/.local/share/opencode2/bin/opencode2" >/dev/null
chmod +x "$BIN/"* "$TEST_HOME/.local/bin/opencode2" \
  "$TEST_HOME/.local/share/opencode2/bin/opencode2"

render() {
  local file=$1 os=$2 enabled=$3 exec_allowed=$4
  "$CHEZMOI" --config "$TEST_ROOT/config.json" --source "$ROOT" \
    --destination "$TEST_HOME" --override-data \
    "{\"chezmoi\":{\"os\":\"$os\",\"homeDir\":\"$TEST_HOME\"},\"skulk\":{\"enabled\":$enabled,\"allowExec\":$exec_allowed}}" \
    execute-template --file "$ROOT/$file"
}

assert_absent() {
  if grep -q "$1" "$2"; then
    printf 'FAIL: unexpected %s in %s\n' "$1" "$2" >&2
    exit 1
  fi
}

for os in linux darwin; do
  render home/private_dot_config/pitchfork/config.toml.tmpl "$os" true false > "$TEST_ROOT/pitchfork.toml"
  render home/private_dot_config/mise/config.toml.tmpl "$os" true false > "$TEST_ROOT/mise.toml"
  python3 - "$TEST_ROOT" "$TEST_HOME" <<'PY'
import pathlib, sys, tomllib
root, home = pathlib.Path(sys.argv[1]), sys.argv[2]
pitchfork = tomllib.loads((root / "pitchfork.toml").read_text())
mise = tomllib.loads((root / "mise.toml").read_text())
daemon = pitchfork["daemons"]["df-skulk"]
assert daemon["run"] == "skulk daemon"
assert daemon["retry"] and daemon["boot_start"]
assert mise["tools"]["npm:@kitlangton/skulk"] == "0.1.0"
for env in [daemon["env"], mise["env"]]:
    assert env["SKULK_OPENCODE"] == home + "/.local/bin/opencode2"
    assert env["SKULK_ALLOW_EXEC"] == "0"
assert home + "/.local/share/mise/shims" in daemon["env"]["PATH"]
assert "OPENCODE_CONFIG_DIR" not in daemon["env"]
assert "OPENCODE_DB" not in daemon["env"]
PY
  render home/private_dot_config/pitchfork/config.toml.tmpl "$os" false false > "$TEST_ROOT/disabled.toml"
  assert_absent 'df-skulk' "$TEST_ROOT/disabled.toml"
  render home/private_dot_config/pitchfork/config.toml.tmpl "$os" true true |
    grep -q 'SKULK_ALLOW_EXEC = "1"'
done

run_lifecycle() {
  : > "$CALLS"
  render home/.chezmoiscripts/run_after_install-073-skulk-daemon.sh.tmpl linux "$1" false \
    > "$TEST_ROOT/lifecycle.sh"
  HOME="$TEST_HOME" PATH="$BIN:$PATH" \
    bash "$TEST_ROOT/lifecycle.sh" > "$TEST_ROOT/output" 2>&1
}

run_lifecycle true
grep -q '^pitchfork stop df-skulk$' "$CALLS"
grep -q '^pitchfork supervisor start$' "$CALLS"
grep -q '^pitchfork start --quiet df-skulk$' "$CALLS"
grep -q '^mise exec -- skulk status$' "$CALLS"
# Reapplication still stops before starting and never installs another service.
run_lifecycle true
grep -q '^pitchfork start --quiet df-skulk$' "$CALLS"
run_lifecycle false
grep -q '^pitchfork stop df-skulk$' "$CALLS"
assert_absent 'start\|mise' "$CALLS"

MISSING_TOOL=bun run_lifecycle true
grep -q 'bun not installed' "$TEST_ROOT/output"
assert_absent '^pitchfork start' "$CALLS"

START_RC=1 run_lifecycle true
grep -q 'Failed to start df-skulk' "$TEST_ROOT/output"
assert_absent '^mise exec' "$CALLS"

HEALTH_RC=1 run_lifecycle true
grep -q 'Skulk health probe failed' "$TEST_ROOT/output"

HEALTH_STOPPED=1 run_lifecycle true
grep -q 'Skulk health probe failed' "$TEST_ROOT/output"

rm "$TEST_HOME/.local/share/opencode2/bin/opencode2"
run_lifecycle true
grep -q 'OpenCode 2 not installed' "$TEST_ROOT/output"
assert_absent '^pitchfork start' "$CALLS"

printf 'PASS: Skulk configuration and lifecycle\n'
