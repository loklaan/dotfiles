#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Resurrect Post-Restore Hook                                                 |
#|                                                                            |
#| Resumes saved code agent sessions in their original tmux panes after       |
#| a tmux-resurrect restore. Supports Claude Code, Codex CLI, and OpenCode.  |
#| Called via @resurrect-hook-post-restore-all.                               |
#|                                                                            |
#| Rather than racing zsh startup with tmux send-keys (which collides with    |
#| the Zsh Line Editor, completion widgets, and partial .zshrc loading),     |
#| this writes a per-pane drop file in the per-uid agent-state dir and       |
#| lets the shell source it from .zshrc once initialisation is complete.    |
#| The shell decides when it's ready; we don't guess.                       |
#|----------------------------------------------------------------------------|

set -euo pipefail

RESURRECT_DIR="${HOME}/.tmux/resurrect"
INPUT="$RESURRECT_DIR/code-agent-sessions.json"
LEGACY_INPUT="$RESURRECT_DIR/claude-sessions.json"

DROP_PREFIX="resume-"
STALE_MINUTES=60

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=state-dir.sh
source "$DIR/state-dir.sh"
# shellcheck source=agents/claude.sh
source "$DIR/agents/claude.sh"
# shellcheck source=agents/codex.sh
source "$DIR/agents/codex.sh"
# shellcheck source=agents/opencode.sh
source "$DIR/agents/opencode.sh"

# Drop files now live in the per-uid guarded dir, not world-shared ${TMPDIR:-/tmp}
# (finding #1). exit 0 on guard refusal: never fall back to an unsafe location.
DROP_DIR="$(tcsa_state_dir)" || exit 0

posix_quote() {
    printf "'"
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
    printf "'"
}

# Sweep drop files older than STALE_MINUTES so a previously failed restore
# doesn't leak commands into future shells.
find "$DROP_DIR" -maxdepth 1 -name "${DROP_PREFIX}*.zsh" \
    -mmin "+${STALE_MINUTES}" -delete 2>/dev/null || true

# Legacy migration: if only old sidecar exists, treat entries as claude
if [[ ! -f "$INPUT" && -f "$LEGACY_INPUT" ]]; then
    jq '[.[] | . + {agent: "claude", meta: {model: (.model // ""), flags: (.flags // "")}}]' \
        "$LEGACY_INPUT" > "$INPUT" 2>/dev/null || true
fi

[[ -f "$INPUT" ]] || exit 0

count=$(jq length "$INPUT")
for ((i = 0; i < count; i++)); do
    entry=$(jq -c ".[$i]" "$INPUT")
    coordinate=$(jq -r '.pane' <<< "$entry")
    agent=$(jq -r '.agent // "claude"' <<< "$entry")
    cwd=$(jq -r '.cwd' <<< "$entry")

    # Resolve the saved coordinate (session:window.pane) to the current
    # %pane_id so the shell's own $TMUX_PANE lookup finds our drop file.
    # Pane IDs are reassigned on restore; coordinates are preserved.
    pane_id=$(tmux display-message -p -t "$coordinate" '#{pane_id}' 2>/dev/null || true)
    [[ -n "$pane_id" ]] || continue

    pane_cmd=$(tmux display-message -p -t "$pane_id" '#{pane_current_command}' 2>/dev/null || true)
    case "$pane_cmd" in
        bash|zsh|fish|sh|dash|ksh) ;;
        *) continue ;;
    esac

    cmd=""
    case "$agent" in
        claude)   cmd=$(restore_cmd_claude "$entry") ;;
        codex)    cmd=$(restore_cmd_codex "$entry") ;;
        opencode) cmd=$(restore_cmd_opencode "$entry") ;;
        *) continue ;;
    esac

    [[ -n "$cmd" ]] || continue

    quoted_cwd=$(posix_quote "$cwd")

    # Strip the leading `%` from pane_id to match how init/tmux-resume.zsh
    # strips its own $TMUX_PANE. Both sides derive the same filename.
    drop_file="${DROP_DIR}/${DROP_PREFIX}${pane_id#%}.zsh"

    # Atomic write so a half-written file is never sourced.
    tmp="${drop_file}.tmp.$$"
    {
        printf 'cd %s\n' "$quoted_cwd"
        printf '%s\n' "$cmd"
    } > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$drop_file"

    # The resurrect plugin respawns pane shells (restore_all_panes) *before*
    # firing this post-restore-all hook. A fast-booting pane therefore runs
    # init/tmux-resume.zsh — claiming a not-yet-written drop file — and would
    # never resume. Poke it to re-attempt the claim now the file exists.
    #
    # Send only the literal function name, never the agent command: if zsh is
    # still mid-init the terminal buffers these keys until its first prompt
    # (function defined by then); if boot already claimed, the function's
    # atomic `mv` no-ops. Resume runs exactly once, at an idle prompt — this is
    # the ZLE-safety the original send-keys-free design depended on.
    #
    # Only poke panes still showing a shell, so we never clobber a pane the
    # user or a prior poke already launched into.
    poke_cmd=$(tmux display-message -p -t "$pane_id" '#{pane_current_command}' 2>/dev/null || true)
    case "$poke_cmd" in
        bash|zsh|fish|sh|dash|ksh)
            tmux send-keys -t "$pane_id" ' _tmux_resume_claim' Enter 2>/dev/null || true
            ;;
    esac
done

