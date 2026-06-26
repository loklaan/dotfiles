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
    # Mirror state-dir.sh's tcsa_state_dir_path() inline — we must NOT source
    # that file into interactive zsh startup. ${XDG_STATE_HOME:-$HOME/.local/state}
    # with one trailing slash stripped, then /tmux-code-agents: byte-for-byte
    # parity with the bash and TypeScript resolvers. NOT the old shared /tmp path
    # (finding #1: a world-shared dir let any local user pre-plant the drop file).
    local base="${XDG_STATE_HOME:-$HOME/.local/state}"
    base="${base%/}"
    local resume_file="${base}/tmux-code-agents/resume-${TMUX_PANE#%}.zsh"
    local resume_src="${resume_file}.claim.$$"
    # Atomic claim (single source of truth for the boot/poke double-trigger):
    # whoever renames the shared path first wins; the loser's mv no-ops.
    mv -f "$resume_file" "$resume_src" 2>/dev/null || return 0
    # Pre-source guards on the CLAIMED file (finding #1), in a load-bearing
    # order: refuse a symlink FIRST so the later regular-file and ownership
    # checks operate on a path already proven not to be a symlink (stat's
    # symlink-following differs across platforms; testing -L first makes it
    # moot). Warn and bail before sourcing on any failure — never source a
    # file that fails a check.
    if [[ -L "$resume_src" ]]; then
        printf 'tmux-resume: refusing %s: it is a symlink, not sourcing\n' "$resume_src" >&2
        rm -f "$resume_src"
        return 0
    fi
    if [[ ! -f "$resume_src" ]]; then
        printf 'tmux-resume: refusing %s: not a regular file, not sourcing\n' "$resume_src" >&2
        rm -f "$resume_src"
        return 0
    fi
    # Ownership: stat the claimed file's owner uid (BSD `-f` / GNU `-c`, with a
    # fallback so it works on both) and require it to equal the current uid. An
    # empty result (stat failed or the file vanished) fails the test and is
    # refused — safe by default.
    local owner_uid
    owner_uid="$(stat -f '%u' "$resume_src" 2>/dev/null || stat -c '%u' "$resume_src" 2>/dev/null)"
    if [[ "$owner_uid" != "$(id -u)" ]]; then
        printf 'tmux-resume: refusing %s: not owned by current uid, not sourcing\n' "$resume_src" >&2
        rm -f "$resume_src"
        return 0
    fi
    # shellcheck disable=SC1090  # drop file path is runtime-computed by design
    source "$resume_src"
    rm -f "$resume_src"
}

# Claim on boot. If the drop file isn't written yet (fast pane), this no-ops and
# the producer poke delivers it once the pane is idle.
_tmux_resume_claim
