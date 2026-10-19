#!/usr/bin/env bash
# checkout-sync.sh — keep a machine-local git checkout on its branch tip and
# rebuild it. Sourced by run_after_install-073-sync-checkouts.sh after
# bash-logging.sh; the checkouts themselves are [data.checkouts.<name>] entries
# in the machine's chezmoi.toml.
#
# cs_sync never discards work: it only fast-forwards, and leaves a checkout
# alone when it is dirty, ahead of origin, off its branch, already being
# synced, or in use by a listed process. When the build fails, it moves back to
# the previous commit and builds that again, so the checkout keeps working
# artefacts. Running programs keep what they loaded until they restart.
#
# Returns 0 when current or updated, 1 when the build failed, 3 when skipped.

# cs_busy <name...>: true when a listed program runs in a terminal, or when
# processes cannot be listed (fail closed). Background processes have tty ?
# (Linux) or ?? (macOS); a trailing .exe on the program name is ignored.
cs_busy() {
  [ "$#" -gt 0 ] || return 1
  local procs
  procs=$(ps -axo tty=,comm= 2>/dev/null) || return 0
  printf '%s\n' "$procs" | awk -v names=" $* " '
    $1 !~ /^\?+$/ { n = split($2, a, "/"); c = a[n]; sub(/\.exe$/, "", c); if (index(names, " " c " ")) hit = 1 }
    END { exit !hit }'
}

# cs_build <log> <command>: run the build command in the current directory,
# bounded to 25 minutes when timeout exists.
cs_build() {
  local log=$1 cmd=$2
  local -a bound=()
  command -v timeout >/dev/null 2>&1 && bound=(timeout 1500)
  CI=1 ${bound[@]+"${bound[@]}"} bash -euo pipefail -c "$cmd" >"$log" 2>&1 </dev/null
}

# cs_sync <name> <path> <branch|""> <build|""> [busy program...]
cs_sync() {
  local name=$1 dir=$2 branch=$3 build=$4
  shift 4
  (
    set -uf
    skip() { log_skip "${name}: $*"; exit 3; }
    export PATH="${HOME}/.local/share/mise/shims:${HOME}/.local/bin:${PATH}" GIT_TERMINAL_PROMPT=0

    cd "$dir" 2>/dev/null || skip "no checkout at ${dir}"
    local gitdir cur want lock stamp log
    gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || skip "${dir} is not a git checkout"
    [ -n "$branch" ] || branch=$(git symbolic-ref -q --short HEAD) || skip "detached HEAD"
    [ "$(git symbolic-ref -q --short HEAD)" = "$branch" ] || skip "not on ${branch}"

    lock="${gitdir}/checkout-sync.lock" # a symlink whose target is the apply script's PID
    if ! ln -s "$$" "$lock" 2>/dev/null; then
      kill -0 "$(readlink "$lock" 2>/dev/null)" 2>/dev/null && skip "another sync holds ${lock}"
      rm -f "$lock"
      ln -s "$$" "$lock" 2>/dev/null || skip "cannot take ${lock}"
    fi
    trap 'rm -f "$lock"' EXIT
    stamp="${gitdir}/checkout-sync.built" # the commit the last successful build used
    log="${gitdir}/checkout-sync.log"

    [ -z "$(git status --porcelain --untracked-files=no)" ] || skip "uncommitted changes"
    # Explicit refspec: a stale configured refspec must not break the fetch.
    local -a bound=()
    command -v timeout >/dev/null 2>&1 && bound=(timeout 120)
    ${bound[@]+"${bound[@]}"} git fetch -q origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" 2>/dev/null ||
      skip "cannot fetch origin/${branch}"
    want=$(git rev-parse "refs/remotes/origin/${branch}") || skip "cannot resolve origin/${branch}"
    cur=$(git rev-parse HEAD) || skip "cannot resolve HEAD"

    if [ "$cur" = "$want" ] && { [ -z "$build" ] || [ "$(cat "$stamp" 2>/dev/null)" = "$cur" ]; }; then
      log_detail "${name}: up to date at ${cur:0:7}"
      exit 0
    fi
    cs_busy "$@" && skip "$* is open in a terminal (or processes cannot be listed); close it and apply again"
    git merge-base --is-ancestor "$cur" "$want" || skip "${cur:0:7} has commits that are not on origin/${branch}"

    if [ "$cur" != "$want" ]; then
      local out
      out=$(git merge --ff-only --no-overwrite-ignore -q "$want" 2>&1) || skip "fast-forward refused: ${out}"
    fi
    if [ -z "$build" ]; then
      log_ok "${name}: at ${want:0:7} (was ${cur:0:7})"
      exit 0
    fi
    if cs_build "$log" "$build"; then
      printf '%s\n' "$want" >"$stamp"
      log_ok "${name}: built ${want:0:7} (was ${cur:0:7})"
      exit 0
    fi

    rm -f "$stamp"
    log_fail "${name}: build failed at ${want:0:7} (log: ${log})"
    tail -n 20 "$log" | sed 's/^/    /' >&2
    [ "$cur" != "$want" ] || exit 1
    git reset -q --keep "$cur" || { log_fail "${name}: could not move back to ${cur:0:7}"; exit 1; }
    if cs_build "${log}.previous" "$build"; then
      printf '%s\n' "$cur" >"$stamp"
      log_warn "${name}: back on ${cur:0:7}, rebuilt"
    else
      log_fail "${name}: back on ${cur:0:7}, but its build failed too (log: ${log}.previous)"
    fi
    exit 1
  )
}
