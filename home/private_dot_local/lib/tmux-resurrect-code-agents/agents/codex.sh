#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Codex CLI Agent Module                                                      |
#|                                                                            |
#| Provides detect and restore_cmd functions for Codex CLI sessions.          |
#| Sourced by save.sh and restore.sh — do not execute directly.               |
#|----------------------------------------------------------------------------|

# detect_codex PANE_ID CWD
#   Check hook-tracked state first, then fall back to filesystem scan.
#   Prints JSON entry on success, returns 1 if no session found.
detect_codex() {
    local pane_id="$1" cwd="$2"
    local state_file="$STATE_DIR/$pane_id"

    # Primary: hook-tracked state from SessionStart
    if [[ -f "$state_file" ]]; then
        local agent
        agent=$(jq -r '.agent // empty' "$state_file" 2>/dev/null) || true
        if [[ "$agent" == "codex" ]]; then
            local session_id
            session_id=$(jq -r '.session_id // empty' "$state_file")
            if [[ -n "$session_id" ]]; then
                jq -n \
                    --arg pane "$pane_id" \
                    --arg agent "codex" \
                    --arg sid "$session_id" \
                    --arg cwd "$cwd" \
                    '{pane: $pane, agent: $agent, session_id: $sid, cwd: $cwd, meta: {}}'
                return 0
            fi
        fi
    fi

    # Fallback: scan ~/.codex/sessions/ for most recent session matching cwd
    local codex_sessions="${HOME}/.codex/sessions"
    [[ -d "$codex_sessions" ]] || return 1

    local found_id=""
    local found_time=0

    # Walk date dirs in reverse order (most recent first)
    while IFS= read -r date_dir; do
        [[ -d "$date_dir" ]] || continue
        while IFS= read -r session_dir; do
            local meta="$session_dir/session.json"
            [[ -f "$meta" ]] || continue

            local sess_cwd sess_id updated
            sess_cwd=$(jq -r '.cwd // empty' "$meta" 2>/dev/null) || continue
            [[ "$sess_cwd" == "$cwd" ]] || continue

            sess_id=$(jq -r '.thread_id // .session_id // empty' "$meta" 2>/dev/null) || continue
            [[ -n "$sess_id" ]] || continue

            # Use file modification time as proxy for recency
            updated=$(stat -f '%m' "$meta" 2>/dev/null || stat -c '%Y' "$meta" 2>/dev/null) || continue
            if (( updated > found_time )); then
                found_time=$updated
                found_id=$sess_id
            fi
        done < <(find "$date_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    done < <(find "$codex_sessions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)

    [[ -n "$found_id" ]] || return 1

    jq -n \
        --arg pane "$pane_id" \
        --arg agent "codex" \
        --arg sid "$found_id" \
        --arg cwd "$cwd" \
        '{pane: $pane, agent: $agent, session_id: $sid, cwd: $cwd, meta: {}}'
}

# restore_cmd_codex ENTRY_JSON
#   Build the shell command to resume a Codex CLI session.
#   Prints the command string to stdout.
restore_cmd_codex() {
    local entry="$1"
    local session_id
    session_id=$(jq -r '.session_id' <<< "$entry")

    printf 'codex resume %s' "$(posix_quote "$session_id")"
}
