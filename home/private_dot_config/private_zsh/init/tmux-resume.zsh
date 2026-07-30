# Surfaces a code agent session dropped by tmux-resurrect's post-restore hook
# (see ~/.local/lib/tmux-resurrect-code-agents/restore.sh).
#
# We PRINT the resume command as a copy-pasteable block rather than executing
# it. The user decides whether (and when) to resume — a restored pane lands at
# a clean prompt in the right cwd with the exact command ready to paste. This
# removes the whole class of "a poisoned drop file gets sourced into my shell"
# risk: nothing here ever runs the file's contents.
#
# Two callers race for the same per-pane drop file and must consume it exactly
# once:
#   1. shell boot   — this file is sourced from .zshrc as the pane's zsh starts.
#   2. producer poke — restore.sh send-keys `_tmux_resume_claim` into panes that
#      are already idle at a prompt, because the resurrect plugin respawns pane
#      shells (restore_all_panes) *before* firing the post-restore-all hook that
#      writes the drop files. Fast-booting panes pass this line before the file
#      exists, so without the poke they would silently never surface.
#
# The atomic `mv`-claim is the single source of truth for "who consumes it":
# whoever renames the shared path first wins; the loser's `mv` no-ops. This
# makes the boot/poke double-trigger safe (never double-printed) and closes the
# original check-then-read TOCTOU against restore.sh's `find -delete` sweep.
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
    # Guards on the CLAIMED file (finding #1), in a load-bearing order: refuse a
    # symlink FIRST so the later regular-file and ownership checks operate on a
    # path already proven not to be a symlink. We only PRINT the contents, but a
    # symlinked / wrong-owner / non-regular file is untrustworthy enough that we
    # will not suggest its command to the user. Warn and bail on any failure.
    if [[ -L "$resume_src" ]]; then
        printf 'tmux-resume: refusing %s: it is a symlink, not surfacing\n' "$resume_src" >&2
        rm -f "$resume_src"
        return 0
    fi
    if [[ ! -f "$resume_src" ]]; then
        printf 'tmux-resume: refusing %s: not a regular file, not surfacing\n' "$resume_src" >&2
        rm -f "$resume_src"
        return 0
    fi
    # Ownership: require the claimed file to belong to the current user. Use
    # zsh's built-in `[[ -O ]]` test — the same portable ownership primitive
    # state-dir.sh relies on. (The old `stat -f '%u' || stat -c '%u'` idiom was
    # broken on GNU/Linux: coreutils `stat -f` means "filesystem status" and
    # exits 0 while printing an fs blob, so the `||` fallback never fired and
    # the uid comparison always failed — a false "not owned by current uid" on
    # every Linux box.) `-O` needs no external binary and cannot be fooled by
    # an output-format quirk.
    if [[ ! -O "$resume_src" ]]; then
        printf 'tmux-resume: refusing %s: not owned by current uid, not surfacing\n' "$resume_src" >&2
        rm -f "$resume_src"
        return 0
    fi

    # Parse the two-line drop file written by restore.sh:
    #     cd '<cwd>'
    #     <agent resume command>
    # Both lines are already valid, posix-quoted zsh — safe to display and to
    # copy-paste verbatim. We read (never execute) them.
    local resume_cwd_line resume_cmd_line
    resume_cwd_line="$(sed -n '1p' "$resume_src")"
    resume_cmd_line="$(sed -n '2p' "$resume_src")"
    rm -f "$resume_src"

    [[ -n "$resume_cmd_line" ]] || return 0

    # Strip the `cd '...'` wrapper for a friendlier display of the directory,
    # falling back to the raw line if it doesn't match the expected shape.
    local resume_dir="$resume_cwd_line"
    if [[ "$resume_cwd_line" == cd\ * ]]; then
        resume_dir="${resume_cwd_line#cd }"
        resume_dir="${(Q)resume_dir}"   # zsh: remove one level of quoting
    fi

    # The full copy-pasteable one-liner (cd + resume, joined with &&).
    local resume_oneliner="${resume_cwd_line} && ${resume_cmd_line}"

    # %F{8} (bright-black/grey) is in the basic 16-colour set, so it renders as
    # \e[90m on every terminal — unlike %F{242}, which mangles to a bogus SGR on
    # terminals lacking 256-colour support.
    print -P ""
    print -P "%F{cyan}╭─ code-agent session available in this pane ────────────────%f"
    print -P "%F{cyan}│%f  %F{8}dir%f  ${resume_dir}"
    print -P "%F{cyan}│%f  %F{8}run%f  %F{green}${resume_cmd_line}%f"
    print -P "%F{cyan}├────────────────────────────────────────────────────────────%f"
    print -P "%F{cyan}│%f  %F{8}copy-paste to resume:%f"
    print -P "%F{cyan}│%f"
    print -rP -- "%F{cyan}│%f    ${resume_oneliner}"
    print -P "%F{cyan}│%f"
    print -P "%F{cyan}╰────────────────────────────────────────────────────────────%f"
    print -P ""
}

# Surface on boot. If the drop file isn't written yet (fast pane), this no-ops
# and the producer poke delivers it once the pane is idle.
_tmux_resume_claim
