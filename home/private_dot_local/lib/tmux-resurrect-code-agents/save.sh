#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Resurrect Post-Save Hook                                                    |
#|                                                                            |
#| Writes a sidecar JSON mapping tmux pane coordinates to code agent          |
#| session IDs. Checks hook-tracked state first, then falls back to           |
#| agent-specific detection. Called via @resurrect-hook-post-save-all.        |
#|----------------------------------------------------------------------------|

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=state-dir.sh
source "$DIR/state-dir.sh"
# shellcheck source=resurrect-dir.sh
source "$DIR/resurrect-dir.sh"
# Resolve the guarded state dir BEFORE sourcing the agent modules so their
# detect_* readers inherit it; exit 0 on refusal so the post-save hook never
# writes the sidecar from an unsafe dir nor disables tmux-resurrect.
STATE_DIR="$(tcsa_state_dir)" || exit 0

RESURRECT_DIR="$(tcsa_resurrect_dir)" || exit 0
mkdir -p "$RESURRECT_DIR"
OUTPUT="$RESURRECT_DIR/code-agent-sessions.json"

# Source agent modules
# shellcheck source=agents/opencode.sh
source "$DIR/agents/opencode.sh"

entries='[]'

while IFS='|' read -r pane_id coordinate cwd; do
    entry=""

    # A state file alone is not evidence: it is a claim that must still be
    # backed by a live process (LIVENESS CONTRACT in state-dir.sh). Without this
    # gate a claim left behind by a quit agent is re-attributed to whatever
    # unrelated pane later inherits that pane id, because tmux reassigns ids
    # from %0 in every new server.
    state_file="$STATE_DIR/$pane_id"
    if tcsa_claim_is_live "$state_file" "$pane_id"; then
        agent=$(jq -r '.agent // empty' "$state_file" 2>/dev/null) || agent=""
        case "$agent" in
            opencode) entry=$(detect_opencode "$pane_id" "$cwd" 2>/dev/null) || entry="" ;;
        esac
    fi

    if [[ -n "$entry" ]]; then
        entry=$(jq --arg pane "$coordinate" '.pane = $pane' <<< "$entry")
        entries=$(jq --argjson e "$entry" '. + [$e]' <<< "$entries")
    fi
done < <(tmux list-panes -a -F '#{pane_id}|#{session_name}:#{window_index}.#{pane_index}|#{pane_current_path}')

jq '.' <<< "$entries" > "$OUTPUT"
