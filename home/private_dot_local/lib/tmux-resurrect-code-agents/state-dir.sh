#!/usr/bin/env bash
# shellcheck shell=bash

#|----------------------------------------------------------------------------|
#| Shared agent-state directory resolver + ownership guard                     |
#|                                                                            |
#| The ONE place that decides where code-agent session state lives and that   |
#| asserts the directory is safe to use. Sourced by save.sh and restore.sh     |
#| (bash hooks); the interactive tmux-resume zsh module mirrors the path        |
#| resolver inline rather than sourcing this file.                             |
#|                                                                            |
#| Path: ${XDG_STATE_HOME:-$HOME/.local/state}/tmux-code-agents               |
#| (NOT the world-shared ${TMPDIR:-/tmp} path of old — security finding #3:   |
#| any local user could pre-create /tmp/tmux-code-agent-sessions and poison   |
#| the state files a restore would later execute.)                            |
#|                                                                            |
#| CONTRACT — this file is SOURCED, including into interactive zsh:           |
#|   * It MUST NOT run `set -euo pipefail` or any `set` that mutates the      |
#|     caller's shell options.                                                 |
#|   * It MUST have no side effects at source time — it only defines          |
#|     functions. The guard runs (and may mkdir/chmod) only when CALLED.      |
#|   * The functions NEVER call `exit`; they `return 1` on failure so the     |
#|     caller decides between `exit 0` (a hook) and `return` (a sourced       |
#|     shell). Exiting here would kill an interactive zsh.                     |
#|----------------------------------------------------------------------------|

# tcsa_state_dir_path
#   Pure resolver: print the agent-state dir path. No side effects, no I/O.
#   Mirrored byte-for-byte by the zsh and TypeScript resolvers (parity-tested).
tcsa_state_dir_path() {
    local base="${XDG_STATE_HOME:-$HOME/.local/state}"
    base="${base%/}"
    printf '%s/tmux-code-agents\n' "$base"
}

# tcsa_state_dir
#   Resolve, create, and guard the agent-state dir. On success prints the path
#   and returns 0. On any guard failure prints a specific warning to stderr and
#   returns 1 — it NEVER exits.
#
#   Guard order is load-bearing: the symlink (-L) test MUST precede the
#   ownership (-O) test. -O follows symlinks, so an attacker-owned symlink that
#   targets a directory the current user happens to own would pass -O; testing
#   -L first refuses the symlink before -O is ever consulted.
tcsa_state_dir() {
    local dir
    dir="$(tcsa_state_dir_path)"

    # 1. Symlink check FIRST, before any mkdir or ownership test.
    if [ -L "$dir" ]; then
        printf 'tmux-resurrect-code-agents: refusing state dir %s: it is a symlink (expected a real, user-owned directory)\n' "$dir" >&2
        return 1
    fi

    # 2. Create it (mode 0700) if absent.
    if [ ! -d "$dir" ]; then
        if ! mkdir -p "$dir" 2>/dev/null; then
            printf 'tmux-resurrect-code-agents: cannot create state dir %s (check permissions on its parent)\n' "$dir" >&2
            return 1
        fi
    fi

    # 3. Re-assert after mkdir to close the create-time symlink race, then
    #    confirm it really is a directory.
    if [ -L "$dir" ]; then
        printf 'tmux-resurrect-code-agents: refusing state dir %s: it is a symlink (expected a real, user-owned directory)\n' "$dir" >&2
        return 1
    fi
    if [ ! -d "$dir" ]; then
        printf 'tmux-resurrect-code-agents: refusing state dir %s: not a directory\n' "$dir" >&2
        return 1
    fi

    # 4. Ownership: must belong to the current effective uid.
    if [ ! -O "$dir" ]; then
        printf 'tmux-resurrect-code-agents: refusing state dir %s: not owned by the current user (uid %s)\n' "$dir" "$(id -u 2>/dev/null || printf '?')" >&2
        return 1
    fi

    # 5. Owner confirmed — safe to repair the mode on a user-owned directory.
    if ! chmod 700 "$dir" 2>/dev/null; then
        printf 'tmux-resurrect-code-agents: cannot chmod 700 state dir %s\n' "$dir" >&2
        return 1
    fi

    printf '%s\n' "$dir"
    return 0
}

#|----------------------------------------------------------------------------|
#| LIVENESS CONTRACT                                                          |
#|                                                                            |
#| A state file is a CLAIM: "pane %N is hosting code-agent session X". The     |
#| claim carries proof of its own liveness so a reader can verify it without   |
#| trusting that anyone remembered to retract it:                              |
#|                                                                            |
#|     .claim.pid    the agent process that made the claim                     |
#|     .claim.start  that process's start time, whitespace-normalised          |
#|     .claim.pane   the pane the claim is about (self-consistency check)      |
#|                                                                            |
#| Why proof-of-liveness and not cleanup-on-exit: no exit hook is reliable.    |
#| Measured against opencode 1.18.23, the plugin `dispose` hook does NOT fire  |
#| on SIGINT or SIGTERM (only on an explicit POST /instance/dispose), and no   |
#| hook of any kind can fire on SIGKILL, OOM, or tmux server teardown. An      |
#| unverifiable claim therefore outlives its process, and because tmux         |
#| reassigns pane ids from %0 in every new server, a leaked claim gets         |
#| silently re-attributed to an unrelated future pane.                         |
#|                                                                            |
#| Why not an age heuristic: mtime is NOT a liveness proxy. Writers only       |
#| rewrite the file when the tracked session CHANGES, so a session held open   |
#| for weeks has a weeks-old mtime and is perfectly live. Ageing claims out    |
#| would delete live state.                                                    |
#|                                                                            |
#| HARD CUT: a claim that cannot prove liveness is refused, never aged out.    |
#| Files written before this contract existed carry no .claim and are refused  |
#| outright. That is deliberate — the alternative is guessing from mtime.      |
#|----------------------------------------------------------------------------|

# tcsa_normalise_ws TEXT
#   Collapse every whitespace run to one space and strip the ends. The ONE
#   definition of the comparison form for .claim.start, mirrored in the
#   TypeScript writer as `s.replace(/\s+/g, " ").trim()`. `ps -o lstart=`
#   pads its output differently across platforms and versions, so writer and
#   reader must agree on a normal form rather than on raw bytes.
tcsa_normalise_ws() {
    printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

# tcsa_claim_is_live STATE_FILE [EXPECTED_PANE]
#   Verify the claim in STATE_FILE is still backed by a live process. Prints
#   nothing. Returns 0 when live, 1 otherwise. NEVER exits (this file is
#   sourced, including into interactive zsh).
#
#   `kill -0` alone is not enough: pids are recycled, so a long-dead agent's
#   pid can be alive again as something unrelated. Matching the recorded start
#   time is what makes the identity check sound.
tcsa_claim_is_live() {
    local state_file="$1" expected_pane="${2:-}"
    local pid recorded_start recorded_pane live_start

    [ -n "$state_file" ] || return 1
    [ -f "$state_file" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    pid=$(jq -r '.claim.pid // empty' "$state_file" 2>/dev/null) || return 1
    recorded_start=$(jq -r '.claim.start // empty' "$state_file" 2>/dev/null) || return 1

    # No claim, or a partial one: refused. This is the hard cut.
    [ -n "$pid" ] || return 1
    [ -n "$recorded_start" ] || return 1

    # Reject a non-numeric pid before it reaches `kill`, so a hand-edited or
    # poisoned file cannot turn into a signal to a process group.
    case "$pid" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$pid" -gt 0 ] 2>/dev/null || return 1

    # A claim about a different pane than the file it lives in is incoherent;
    # treat it as untrustworthy rather than guessing which field is right.
    if [ -n "$expected_pane" ]; then
        recorded_pane=$(jq -r '.claim.pane // empty' "$state_file" 2>/dev/null) || return 1
        [ "$recorded_pane" = "$expected_pane" ] || return 1
    fi

    kill -0 "$pid" 2>/dev/null || return 1

    live_start=$(ps -o lstart= -p "$pid" 2>/dev/null) || return 1
    [ -n "$live_start" ] || return 1
    [ "$(tcsa_normalise_ws "$live_start")" = "$recorded_start" ] || return 1

    return 0
}
