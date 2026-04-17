#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Code Agent Session Tracking Hook                                            |
#|                                                                            |
#| Records the session ID and invocation flags for the current tmux pane so   |
#| tmux-resurrect can restore it after a tmux server restart. Receives        |
#| session JSON on stdin. Called by Claude Code (SessionStart) and Codex      |
#| (SessionStart) hooks.                                                      |
#|                                                                            |
#| Usage: bash track.sh <agent>                                               |
#|   agent: "claude" or "codex"                                               |
#|----------------------------------------------------------------------------|

set -euo pipefail

[[ -z "${TMUX_PANE:-}" ]] && exit 0

agent="${1:-}"
[[ -n "$agent" ]] || exit 0

STATE_DIR="${TMPDIR:-/tmp}/tmux-code-agent-sessions"
mkdir -p -m 0700 "$STATE_DIR"

input=$(cat)
session_id=$(jq -r '.session_id // empty' <<< "$input")
[[ -z "$session_id" ]] && exit 0

model=$(jq -r '.model // empty' <<< "$input")

if [[ "$agent" == "claude" ]]; then
    # Scan ancestor processes for invocation flags that --resume does not restore
    explicit_model=false
    skip_permissions=false
    permission_mode=""
    pid=$PPID

    while [[ $pid -gt 1 ]]; do
        cmd=$(ps -o args= -p "$pid" 2>/dev/null) || break
        [[ "$cmd" == *--model* || "$cmd" == *" -m "* ]] && explicit_model=true
        [[ "$cmd" == *--dangerously-skip-permissions* ]] && skip_permissions=true
        if [[ -z "$permission_mode" && "$cmd" == *--permission-mode* ]]; then
            permission_mode=$(printf '%s' "$cmd" | grep -oE -- '--permission-mode[= ][^ ]+' | head -1)
        fi
        comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
        case "$comm" in bash|zsh|fish|sh|dash|ksh) break ;; esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done

    $explicit_model || model=""

    flags=""
    $skip_permissions && flags="--dangerously-skip-permissions"
    [[ -n "$permission_mode" ]] && flags="${flags:+$flags }$permission_mode"

    jq -n \
        --arg agent "$agent" \
        --arg sid "$session_id" \
        --arg model "$model" \
        --arg flags "$flags" \
        '{agent: $agent, session_id: $sid, model: $model, flags: $flags}' > "$STATE_DIR/$TMUX_PANE"
else
    jq -n \
        --arg agent "$agent" \
        --arg sid "$session_id" \
        --arg model "$model" \
        '{agent: $agent, session_id: $sid, model: $model}' > "$STATE_DIR/$TMUX_PANE"
fi
