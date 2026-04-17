#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Resurrect Post-Save Hook                                                    |
#|                                                                            |
#| Writes a sidecar JSON mapping tmux pane coordinates to code agent          |
#| session IDs. Checks hook-tracked state first, then falls back to           |
#| agent-specific detection. Called via @resurrect-hook-post-save-all.        |
#|----------------------------------------------------------------------------|

set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}/tmux-code-agent-sessions"
RESURRECT_DIR="${HOME}/.tmux/resurrect"
OUTPUT="$RESURRECT_DIR/code-agent-sessions.json"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source agent modules
# shellcheck source=agents/claude.sh
source "$DIR/agents/claude.sh"
# shellcheck source=agents/codex.sh
source "$DIR/agents/codex.sh"
# shellcheck source=agents/opencode.sh
source "$DIR/agents/opencode.sh"

entries='[]'

while IFS='|' read -r pane_id coordinate cwd pane_cmd; do
    entry=""

    # Try hook-tracked state first (works for claude, codex, opencode)
    state_file="$STATE_DIR/$pane_id"
    if [[ -f "$state_file" ]]; then
        agent=$(jq -r '.agent // empty' "$state_file" 2>/dev/null) || agent=""
        case "$agent" in
            claude)   entry=$(detect_claude "$pane_id" "$cwd" 2>/dev/null) || entry="" ;;
            codex)    entry=$(detect_codex "$pane_id" "$cwd" 2>/dev/null) || entry="" ;;
            opencode) entry=$(detect_opencode "$pane_id" "$cwd" 2>/dev/null) || entry="" ;;
        esac
    fi

    # Fallback: detect by running process name
    if [[ -z "$entry" ]]; then
        case "$pane_cmd" in
            codex)    entry=$(detect_codex "$pane_id" "$cwd" 2>/dev/null) || entry="" ;;
            opencode) entry=$(detect_opencode "$pane_id" "$cwd" 2>/dev/null) || entry="" ;;
        esac
    fi

    if [[ -n "$entry" ]]; then
        entry=$(jq --arg pane "$coordinate" '.pane = $pane' <<< "$entry")
        entries=$(jq --argjson e "$entry" '. + [$e]' <<< "$entries")
    fi
done < <(tmux list-panes -a -F '#{pane_id}|#{session_name}:#{window_index}.#{pane_index}|#{pane_current_path}|#{pane_current_command}')

jq '.' <<< "$entries" > "$OUTPUT"
