#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Resurrect `last` Snapshot Guard                                             |
#|                                                                            |
#| Run from tmux.conf (run-shell) at every tmux server start, BEFORE           |
#| tmux-continuum's background auto-restore fires.                             |
#|                                                                            |
#| Why this exists: tmux-resurrect's save is destructive on failure. save_all  |
#| writes straight to the final snapshot path with no temp file, then          |
#| re-points the `last` symlink whenever the new file merely DIFFERS from the  |
#| old one. So a save that runs against a dying or already-dead tmux server    |
#| produces a 0-byte snapshot and still claims it as `last`. Restore then      |
#| succeeds against an empty file and restores nothing — a session comes back  |
#| as a single blank window, silently, with the real state still sitting in    |
#| the previous snapshot right next to it.                                     |
#|                                                                            |
#| This is not hypothetical: a workspace whose tmux server is torn down at     |
#| shutdown accumulates these, and one clobber is enough to lose the session   |
#| permanently, because the next save compares against the empty `last`.       |
#|                                                                            |
#| So before any restore reads it, we assert `last` points at a snapshot with  |
#| actual content, and fall back to the newest snapshot that does. Empty       |
#| snapshots are then deleted, both so they can never be chosen and so they    |
#| stop consuming slots in resurrect's "keep the 5 newest" retention.          |
#|                                                                            |
#| Read-repair only: it never writes a snapshot and never touches tmux state.  |
#| It exits 0 unconditionally, because a guard that breaks the restore it is   |
#| guarding would be worse than the bug.                                       |
#|----------------------------------------------------------------------------|

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=resurrect-dir.sh
source "$DIR/resurrect-dir.sh"

warn() {
    printf 'tmux-resurrect-guard: %s\n' "$1" >&2
}

# Newest snapshot with content, by mtime. Filenames carry a local-time stamp
# and are NOT reliably ordered: a snapshot written by a process in a different
# timezone sorts into the wrong place. mtime is the only sound ordering.
newest_non_empty_snapshot() {
    local resurrect_dir="$1"
    local newest="" candidate
    for candidate in "$resurrect_dir"/tmux_resurrect_*.txt; do
        [ -f "$candidate" ] || continue
        [ -s "$candidate" ] || continue
        if [ -z "$newest" ] || [ "$candidate" -nt "$newest" ]; then
            newest="$candidate"
        fi
    done
    [ -n "$newest" ] || return 1
    printf '%s\n' "$newest"
}

prune_empty_snapshots() {
    local resurrect_dir="$1"
    local candidate
    for candidate in "$resurrect_dir"/tmux_resurrect_*.txt; do
        [ -f "$candidate" ] || continue
        [ -s "$candidate" ] && continue
        rm -f "$candidate" 2>/dev/null || true
    done
}

main() {
    local resurrect_dir last replacement
    resurrect_dir="$(tcsa_resurrect_dir)" || exit 0
    [ -d "$resurrect_dir" ] || exit 0

    last="$resurrect_dir/last"

    # -s follows the symlink, so this one test covers every broken shape:
    # absent, dangling, and present-but-empty.
    if [ ! -s "$last" ]; then
        if replacement="$(newest_non_empty_snapshot "$resurrect_dir")"; then
            # Match resurrect's own relative-symlink form so the directory
            # stays portable between machines.
            if ln -sfn "$(basename "$replacement")" "$last" 2>/dev/null; then
                warn "repointed 'last' at $(basename "$replacement") (previous target was missing or empty)"
            else
                warn "could not repoint 'last' in $resurrect_dir"
            fi
        else
            warn "no non-empty snapshot found in $resurrect_dir, leaving 'last' alone"
        fi
    fi

    prune_empty_snapshots "$resurrect_dir"

    exit 0
}

main
