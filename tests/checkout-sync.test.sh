#!/usr/bin/env bash
# checkout-sync.test.sh — runs checkout-sync.sh and the rendered
# run_after_install-073-sync-checkouts script against throwaway git repos with
# fake pnpm and ps. Never runs chezmoi apply or init; touches only a temp dir.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export HOME="$SB/home" BR=feat
# The repo .mise.toml has [hooks], so mise needs it trusted; this HOME is fresh.
export MISE_TRUSTED_CONFIG_PATHS="$ROOT" MISE_NO_HOOKS=1
BOX="$SB/box"
FAILED=0

g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }
check() {
  local name=$1
  shift
  if "$@"; then return 0; fi
  printf 'FAIL: %s\n' "$name"
  sed 's/^/    | /' "$SB/out"
  FAILED=1
}
head_is() { [ "$(git -C "$BOX" rev-parse HEAD)" = "$1" ]; }
built_is() { [ "$(cat "$BOX/dist" 2>/dev/null)" = "$1" ]; }
stamp_is() { [ "$(cat "$BOX/.git/checkout-sync.built" 2>/dev/null)" = "$1" ]; }
rc_is() { [ "$(cat "$SB/rc")" = "$1" ]; }
said() { grep -q -- "$1" "$SB/out"; }
unlocked() { [ ! -e "$BOX/.git/checkout-sync.lock" ]; }
push() { (cd "$SB/work" && echo "$1" >version.txt && g add -A && g commit -q -m "$1" && git push -q origin "$BR") && git -C "$SB/work" rev-parse HEAD; }
BUILD='pnpm build'
sync() {
  bash -c 'source "$1/home/private_dot_local/lib/bash-logging.sh"; source "$1/home/private_dot_local/lib/checkout-sync.sh"; shift; cs_sync "$@"' \
    _ "$ROOT" box "$BOX" "$@" >"$SB/out" 2>&1
  echo $? >"$SB/rc"
}

mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
cp "$ROOT/home/private_dot_local/lib/bash-logging.sh" "$ROOT/home/private_dot_local/lib/checkout-sync.sh" "$HOME/.local/lib/"
cat >"$HOME/.local/bin/pnpm" <<'EOF'
#!/bin/sh
rm -f dist
if [ -e BROKEN ]; then echo "build exploded"; exit 1; fi
git rev-parse HEAD >dist
EOF
cat >"$HOME/.local/bin/ps" <<'EOF'
#!/bin/sh
if [ -f "$HOME/ps.tty" ]; then cat "$HOME/ps.tty"; else printf '?   opencode.exe\n'; fi
EOF
chmod +x "$HOME/.local/bin/"*

git init -q --bare "$SB/remote.git"
git init -q -b "$BR" "$SB/work"
(cd "$SB/work" && echo v1 >version.txt && printf 'dist\n' >.gitignore && g add -A && g commit -q -m c1 &&
  git remote add origin "$SB/remote.git" && git push -q origin "$BR")
git clone -q -b "$BR" "$SB/remote.git" "$BOX"

C2=$(push c2)
sync "" "$BUILD" opencode
check "behind: exit 0" rc_is 0
check "behind: fast-forwarded" head_is "$C2"
check "behind: built and stamped" built_is "$C2"
check "behind: stamp" stamp_is "$C2"
check "behind: lock released" unlocked

sync "" "$BUILD" opencode
check "current: exit 0 without building" rc_is 0
check "current: says up to date" said 'up to date'

touch "$SB/work/BROKEN"
push c3 >/dev/null
sync "" "$BUILD"
check "broken build: exit 1" rc_is 1
check "broken build: back on the previous commit" head_is "$C2"
check "broken build: previous commit rebuilt" built_is "$C2"
check "broken build: stamp is the previous commit" stamp_is "$C2"
(cd "$SB/work" && g rm -q BROKEN)

echo local >>"$BOX/version.txt"
sync "" "$BUILD"
check "dirty: skipped" rc_is 3
check "dirty: edit kept" grep -q local "$BOX/version.txt"
git -C "$BOX" checkout -q -- version.txt
sync other "$BUILD"
check "wrong branch: skipped" rc_is 3
check "wrong branch: head unmoved" head_is "$C2"

printf 'pts/3   opencode\n' >"$HOME/ps.tty"
sync "" "$BUILD" opencode
check "busy: skipped" rc_is 3
check "busy: head unmoved" head_is "$C2"
printf 'pts/0   collector\n?   opencode.exe\n' >"$HOME/ps.tty"
C4=$(push c4)
sync "" "$BUILD" opencode
check "background or decoy process: not busy" rc_is 0
check "background or decoy process: at c4" head_is "$C4"

ln -s 999999 "$BOX/.git/checkout-sync.lock"
C5=$(push c5)
sync "" "$BUILD"
check "stale lock: reclaimed" rc_is 0
check "stale lock: at c5" head_is "$C5"
sleep 30 &
holder=$!
ln -s "$holder" "$BOX/.git/checkout-sync.lock"
sync "" "$BUILD"
check "live lock: skipped" rc_is 3
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
rm -f "$BOX/.git/checkout-sync.lock"

echo local.env >>"$BOX/.git/info/exclude"
echo mine >"$BOX/local.env"
(cd "$SB/work" && echo theirs >local.env && g add -A && g commit -q -m c6 && git push -q origin "$BR")
sync "" "$BUILD"
check "ignored file in the way: skipped" rc_is 3
check "ignored file in the way: kept" grep -q mine "$BOX/local.env"
check "ignored file in the way: head unmoved" head_is "$C5"
rm -f "$BOX/local.env"

sync "" ""
check "no build: exit 0" rc_is 0
check "no build: fast-forwarded" head_is "$(git -C "$SB/work" rev-parse HEAD)"

# The rendered apply script never fails the apply, even when a build fails.
touch "$SB/work/BROKEN"
push c7 >/dev/null
jq -n --arg box "$BOX" '{data: {checkouts: {box: {path: $box, build: "pnpm build"}, gone: {path: "{homeDir}/missing"}}}}' >"$SB/config.json"
chezmoi execute-template --config "$SB/config.json" -S "$ROOT" -D "$SB/destination" \
  -f "$ROOT/home/.chezmoiscripts/run_after_install-073-sync-checkouts.sh.tmpl" >"$SB/apply.sh"
bash -n "$SB/apply.sh"
bash "$SB/apply.sh" >"$SB/out" 2>&1
echo $? >"$SB/rc"
check "apply script: exit 0 with a failed build and a missing checkout" rc_is 0
check "apply script: reports the failure" said 'build failed'
check "apply script: reports the missing checkout" said 'no checkout at'
echo '{}' >"$SB/empty.json"
[ -z "$(chezmoi execute-template --config "$SB/empty.json" -S "$ROOT" -D "$SB/destination" \
  -f "$ROOT/home/.chezmoiscripts/run_after_install-073-sync-checkouts.sh.tmpl" | tr -d '[:space:]')" ] ||
  { echo "FAIL: apply script renders without checkouts"; FAILED=1; }

[ "$FAILED" = 0 ] && printf 'PASS: checkout sync fast-forwards, rebuilds, rolls back, skips safely, never fails the apply\n'
exit "$FAILED"
