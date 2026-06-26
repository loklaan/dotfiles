#!/usr/bin/env bash
# shellcheck shell=bash

#|----------------------------------------------------------------------------|
#| Shared agent-state directory resolver + ownership guard                     |
#|                                                                            |
#| The ONE place that decides where code-agent session state lives and that   |
#| asserts the directory is safe to use. Sourced by track.sh, save.sh,        |
#| cleanup.sh (bash hooks) and by the interactive tmux-resume zsh module.     |
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
