#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Liveness contract + save.sh gate tests                                      |
#|                                                                            |
#| Run: bash tests/tmux-resurrect-code-agents/liveness.test.sh                 |
#|                                                                            |
#| `tmux` is faked by placing a shim EARLIER in PATH. PATH is never truncated:  |
#| a truncated PATH changes which real binaries resolve and would have the     |
#| harness quietly exercise something other than production behaviour.         |
#| `ps` is deliberately NOT faked here — the whole point is to verify against  |
#| real process liveness.                                                      |
#|                                                                            |
#| Do NOT redirect the save path by overriding HOME or XDG_DATA_HOME. mise     |
#| resolves its tool installs under XDG_DATA_HOME, so overriding it makes      |
#| every mise-shimmed binary (jq here) try to reinstall itself and block       |
#| forever — the same class of trap as truncating PATH. The snapshot directory  |
#| is redirected through tmux's own @resurrect-dir option instead, which is    |
#| the branch tcsa_resurrect_dir prefers. XDG_STATE_HOME is safe to override.  |
#|----------------------------------------------------------------------------|

set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../home/private_dot_local/lib/tmux-resurrect-code-agents" && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else no "$1 (want '$3', got '$2')"; fi; }

# shellcheck source=../../home/private_dot_local/lib/tmux-resurrect-code-agents/state-dir.sh
source "$LIB/state-dir.sh"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

live_start() { tcsa_normalise_ws "$(ps -o lstart= -p "$1" 2>/dev/null)"; }

dead_pid() {
    local victim
    sleep 0.1 &
    victim=$!
    wait "$victim" 2>/dev/null
    printf '%s\n' "$victim"
}

claim_file() {
    local path="$1" pid="$2" start="$3" pane="$4"
    jq -n --arg sid "ses_test" --argjson pid "$pid" --arg start "$start" --arg pane "$pane" \
        '{agent:"opencode", session_id:$sid, claim:{pid:$pid, start:$start, pane:$pane}}' > "$path"
}

printf '\ntcsa_claim_is_live\n'

D="$ROOT/claims"
mkdir -p "$D"

claim_file "$D/%1" "$$" "$(live_start $$)" "%1"
tcsa_claim_is_live "$D/%1" "%1"; check "accepts a claim backed by a live process" "$?" "0"

printf '{"agent":"opencode","session_id":"ses_legacy"}\n' > "$D/%2"
tcsa_claim_is_live "$D/%2" "%2"; check "refuses a pre-contract file with no claim (hard cut)" "$?" "1"

DEAD="$(dead_pid)"
claim_file "$D/%3" "$DEAD" "Sat Aug 29 10:00:00 2026" "%3"
tcsa_claim_is_live "$D/%3" "%3"; check "refuses a claim whose process has exited" "$?" "1"

claim_file "$D/%4" "$$" "Mon Jan 01 00:00:00 2001" "%4"
tcsa_claim_is_live "$D/%4" "%4"; check "refuses a live pid whose start time differs (pid reuse)" "$?" "1"

claim_file "$D/%5" "$$" "$(live_start $$)" "%99"
tcsa_claim_is_live "$D/%5" "%5"; check "refuses a claim about a different pane" "$?" "1"

jq -n --arg s "ses_x" '{agent:"opencode", session_id:$s, claim:{pid:'"$$"'}}' > "$D/%6"
tcsa_claim_is_live "$D/%6" "%6"; check "refuses a partial claim missing the start time" "$?" "1"

jq -n '{agent:"opencode", session_id:"ses_x", claim:{pid:"-1 -9", start:"x", pane:"%7"}}' > "$D/%7"
tcsa_claim_is_live "$D/%7" "%7"; check "refuses a non-numeric pid before it reaches kill" "$?" "1"

tcsa_claim_is_live "$D/%404" "%404"; check "refuses a missing file" "$?" "1"

printf '\nsave.sh liveness gate\n'

run_save() {
    local home="$1"
    local shims="$home/shims"
    mkdir -p "$shims"
    {
        printf '#!/bin/sh\n'
        printf 'case "$1" in\n'
        printf '  show-option) echo %s ;;\n' "$(printf '%q' "$home/resurrect")"
        printf '  list-panes) cat %s ;;\n' "$(printf '%q' "$home/panes")"
        printf 'esac\n'
    } > "$shims/tmux"
    chmod 755 "$shims/tmux"
    env XDG_STATE_HOME="$home/state" PATH="$shims:$PATH" \
        bash "$LIB/save.sh" >/dev/null 2>&1
    cat "$home/resurrect/code-agent-sessions.json" 2>/dev/null
}

case_save() {
    local label="$1" pid="$2" start="$3" pane_in_claim="$4" want="$5"
    local home="$ROOT/save-$RANDOM$RANDOM"
    mkdir -p "$home/state/tmux-code-agents"
    if [[ -n "$pid" ]]; then
        claim_file "$home/state/tmux-code-agents/%1" "$pid" "$start" "$pane_in_claim"
    else
        printf '{"agent":"opencode","session_id":"ses_legacy"}\n' > "$home/state/tmux-code-agents/%1"
    fi
    printf '%%1|main:0.0|/tmp\n' > "$home/panes"
    local got
    got=$(run_save "$home" | jq -r 'length')
    check "$label" "${got:-<none>}" "$want"
}

case_save "records a pane whose agent is still alive" "$$" "$(live_start $$)" "%1" "1"
case_save "drops a pane whose agent has exited" "$(dead_pid)" "Sat Aug 29 10:00:00 2026" "%1" "0"
case_save "drops a pre-contract file (the stale-banner bug)" "" "" "" "0"
case_save "drops a claim naming another pane" "$$" "$(live_start $$)" "%42" "0"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
