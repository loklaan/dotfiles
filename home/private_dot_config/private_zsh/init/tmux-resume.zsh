# Resumes a code agent session dropped by tmux-resurrect's post-restore hook
# (see ~/.local/lib/tmux-resurrect-code-agents/restore.sh).
#
# Two callers race for the same per-pane drop file and must run it exactly once:
#   1. shell boot   — this file is sourced from .zshrc as the pane's zsh starts.
#   2. producer poke — restore.sh send-keys `_tmux_resume_claim` into panes that
#      are already idle at a prompt, because the resurrect plugin respawns pane
#      shells (restore_all_panes) *before* firing the post-restore-all hook that
#      writes the drop files. Fast-booting panes pass this line before the file
#      exists, so without the poke they would silently never resume.
#
# The atomic `mv`-claim is the single source of truth for "who runs it": whoever
# renames the shared path first wins; the loser's `mv` fails and no-ops. This
# makes the boot/poke double-trigger safe (never double-sourced) and closes the
# original check-then-source TOCTOU against restore.sh's `find -delete` sweep.
_tmux_resume_claim() {
    [[ -n "$TMUX_PANE" ]] || return 0
    local resume_file="${TMPDIR:-/tmp}/tmux-resume-${TMUX_PANE#%}.zsh"
    local resume_src="${resume_file}.claim.$$"
    mv -f "$resume_file" "$resume_src" 2>/dev/null || return 0
    source "$resume_src"
    rm -f "$resume_src"
}

# Claim on boot. If the drop file isn't written yet (fast pane), this no-ops and
# the producer poke delivers it once the pane is idle.
_tmux_resume_claim
