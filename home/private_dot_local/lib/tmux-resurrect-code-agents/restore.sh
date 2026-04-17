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
#| this writes a per-pane drop file to $TMPDIR/tmux-resume-<pane>.zsh and    |
#| lets the shell source it from .zshrc once initialisation is complete.    |
#| The shell decides when it's ready; we don't guess.                       |
#|----------------------------------------------------------------------------|

set -euo pipefail

RESURRECT_DIR="${HOME}/.tmux/resurrect"
INPUT="$RESURRECT_DIR/code-agent-sessions.json"
LEGACY_INPUT="$RESURRECT_DIR/claude-sessions.json"

DROP_DIR="${TMPDIR:-/tmp}"
DROP_PREFIX="tmux-resume-"
STALE_MINUTES=60

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=agents/claude.sh
source "$DIR/agents/claude.sh"
# shellcheck source=agents/codex.sh
source "$DIR/agents/codex.sh"
# shellcheck source=agents/opencode.sh
source "$DIR/agents/opencode.sh"

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
done

