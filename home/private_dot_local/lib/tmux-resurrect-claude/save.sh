#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Resurrect Post-Save Hook                                                   |
#|                                                                            |
#| Writes a sidecar JSON mapping tmux pane coordinates to Claude Code        |
#| session IDs and invocation flags. Called via                               |
#| @resurrect-hook-post-save-all.                                            |
#|----------------------------------------------------------------------------|

set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}/tmux-claude-sessions"
RESURRECT_DIR="${HOME}/.tmux/resurrect"
OUTPUT="$RESURRECT_DIR/claude-sessions.json"

[[ -d "$STATE_DIR" ]] || exit 0

entries='[]'

while IFS='|' read -r pane_id coordinate cwd; do
    state_file="$STATE_DIR/$pane_id"
    [[ -f "$state_file" ]] || continue

    # Support both JSON (new) and plain text (legacy) state files
    if jq -e '.session_id' "$state_file" >/dev/null 2>&1; then
        session_id=$(jq -r '.session_id' "$state_file")
        model=$(jq -r '.model // ""' "$state_file")
        flags=$(jq -r '.flags // ""' "$state_file")
    else
        session_id=$(< "$state_file")
        model=""
        flags=""
    fi
    [[ -n "$session_id" ]] || continue

    entries=$(jq \
        --arg pane "$coordinate" \
        --arg sid "$session_id" \
        --arg cwd "$cwd" \
        --arg model "$model" \
        --arg flags "$flags" \
        '. + [{pane: $pane, session_id: $sid, cwd: $cwd, model: $model, flags: $flags}]' \
        <<< "$entries")
done < <(tmux list-panes -a -F '#{pane_id}|#{session_name}:#{window_index}.#{pane_index}|#{pane_current_path}')

jq '.' <<< "$entries" > "$OUTPUT"
