#!/usr/bin/env bash
# shellcheck shell=bash

#|----------------------------------------------------------------------------|
#| Shared tmux-resurrect snapshot directory resolver                           |
#|                                                                            |
#| The ONE place that decides where tmux-resurrect's own snapshot files live.  |
#| Sourced by save.sh (sidecar write), restore.sh (sidecar read) and           |
#| guard-last.sh (the `last` symlink guard).                                   |
#|                                                                            |
#| This MIRRORS tmux-resurrect's scripts/helpers.sh resolution order, because  |
#| guessing it wrong is silent: a sidecar written to a directory resurrect     |
#| never reads is simply never restored, with no error anywhere.               |
#|                                                                            |
#|   1. the @resurrect-dir tmux option, if set                                |
#|   2. else legacy ~/.tmux/resurrect, but ONLY if it already exists           |
#|   3. else ${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect              |
#|                                                                            |
#| Step 2 is why this cannot be hardcoded either way: every machine that has   |
#| ever run an older resurrect keeps using ~/.tmux/resurrect forever, while a  |
#| freshly provisioned box (new home volume, new user) silently moves to the   |
#| XDG path. Both are live in this fleet at once.                              |
#|                                                                            |
#| CONTRACT — this file is SOURCED:                                            |
#|   * It MUST NOT run `set -euo pipefail` or any `set` that mutates the       |
#|     caller's shell options.                                                 |
#|   * It MUST have no side effects at source time — it only defines a         |
#|     function. It NEVER creates the directory; callers decide that.          |
#|   * It NEVER calls `exit`; it returns 1 so the caller chooses its own       |
#|     failure behaviour.                                                      |
#|----------------------------------------------------------------------------|

# tcsa_resurrect_dir
#   Print the directory tmux-resurrect reads and writes its snapshots in.
#   Returns 1 only if the path resolves empty (which should be impossible).
#
#   Reading the @resurrect-dir option needs a live tmux server. Every caller is
#   either a resurrect hook or a tmux run-shell, so a server is always present;
#   if the query fails anyway we fall through to the same defaults resurrect
#   itself would use, rather than failing the caller.
tcsa_resurrect_dir() {
    local dir=""

    if command -v tmux >/dev/null 2>&1; then
        dir="$(tmux show-option -gqv "@resurrect-dir" 2>/dev/null)" || dir=""
    fi

    if [ -n "$dir" ]; then
        # An explicitly set @resurrect-dir may contain the same placeholders
        # resurrect's own resolver expands. The defaults below never do, so
        # this only runs on the option path.
        dir="${dir//\~/$HOME}"
        dir="${dir//\$HOME/$HOME}"
        dir="${dir//\$HOSTNAME/$(hostname 2>/dev/null)}"
    elif [ -d "$HOME/.tmux/resurrect" ]; then
        dir="$HOME/.tmux/resurrect"
    else
        local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
        dir="${data_home%/}/tmux/resurrect"
    fi

    # Strip a trailing slash so callers can append "/name" unconditionally.
    dir="${dir%/}"

    [ -n "$dir" ] || return 1

    printf '%s\n' "$dir"
    return 0
}
