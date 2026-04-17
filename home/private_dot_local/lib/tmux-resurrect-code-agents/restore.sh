#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Resurrect Post-Restore Hook                                                 |
#|                                                                            |
#| Resumes saved code agent sessions in their original tmux panes after       |
#| a tmux-resurrect restore. Supports Claude Code, Codex CLI, and OpenCode.  |
#| Called via @resurrect-hook-post-restore-all.                               |
#|----------------------------------------------------------------------------|

set -euo pipefail

RESURRECT_DIR="${HOME}/.tmux/resurrect"
INPUT="$RESURRECT_DIR/code-agent-sessions.json"
LEGACY_INPUT="$RESURRECT_DIR/claude-sessions.json"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source agent modules
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

# Legacy migration: if only old sidecar exists, treat entries as claude
if [[ ! -f "$INPUT" && -f "$LEGACY_INPUT" ]]; then
    # Add agent field to legacy entries
    jq '[.[] | . + {agent: "claude", meta: {model: (.model // ""), flags: (.flags // "")}}]' \
        "$LEGACY_INPUT" > "$INPUT" 2>/dev/null || true
fi

[[ -f "$INPUT" ]] || exit 0

sleep 2

count=$(jq length "$INPUT")
for ((i = 0; i < count; i++)); do
    entry=$(jq -c ".[$i]" "$INPUT")
    pane=$(jq -r '.pane' <<< "$entry")
    agent=$(jq -r '.agent // "claude"' <<< "$entry")
    cwd=$(jq -r '.cwd' <<< "$entry")

    tmux display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1 || continue

    pane_cmd=$(tmux display-message -p -t "$pane" '#{pane_current_command}')
    case "$pane_cmd" in
        bash|zsh|fish|sh|dash|ksh) ;;
        *) continue ;;
    esac

    quoted_cwd=$(posix_quote "$cwd")

    # Dispatch to agent-specific restore command builder
    cmd=""
    case "$agent" in
        claude)   cmd=$(restore_cmd_claude "$entry") ;;
        codex)    cmd=$(restore_cmd_codex "$entry") ;;
        opencode) cmd=$(restore_cmd_opencode "$entry") ;;
        *) continue ;;
    esac

    [[ -n "$cmd" ]] || continue

    tmux send-keys -t "$pane" \
        "cd $quoted_cwd && $cmd" Enter
done
