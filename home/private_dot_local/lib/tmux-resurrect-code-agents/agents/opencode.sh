#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| OpenCode Agent Module                                                       |
#|                                                                            |
#| Provides detect and restore_cmd functions for OpenCode sessions.           |
#| Sourced by save.sh and restore.sh — do not execute directly.               |
#|----------------------------------------------------------------------------|

# detect_opencode PANE_ID CWD
#   Check hook-tracked state first, then fall back to SQLite query.
#   Prints JSON entry on success, returns 1 if no session found.
detect_opencode() {
    local pane_id="$1" cwd="$2"
    local state_file="$STATE_DIR/$pane_id"

    # Primary: hook-tracked state from OpenCode plugin
    if [[ -f "$state_file" ]]; then
        local agent
        agent=$(jq -r '.agent // empty' "$state_file" 2>/dev/null) || true
        if [[ "$agent" == "opencode" ]]; then
            local session_id
            session_id=$(jq -r '.session_id // empty' "$state_file")
            if [[ -n "$session_id" ]]; then
                jq -n \
                    --arg pane "$pane_id" \
                    --arg agent "opencode" \
                    --arg sid "$session_id" \
                    --arg cwd "$cwd" \
                    '{pane: $pane, agent: $agent, session_id: $sid, cwd: $cwd, meta: {}}'
                return 0
            fi
        fi
    fi

    # Fallback: query SQLite for most recent session in cwd
    local db="$cwd/.opencode/opencode.db"
    [[ -f "$db" ]] || return 1
    command -v sqlite3 >/dev/null 2>&1 || return 1

    local session_id
    session_id=$(sqlite3 "$db" \
        "SELECT id FROM sessions WHERE parent_session_id IS NULL OR parent_session_id = '' ORDER BY updated_at DESC LIMIT 1" \
        2>/dev/null) || return 1
    [[ -n "$session_id" ]] || return 1

    jq -n \
        --arg pane "$pane_id" \
        --arg agent "opencode" \
        --arg sid "$session_id" \
        --arg cwd "$cwd" \
        '{pane: $pane, agent: $agent, session_id: $sid, cwd: $cwd, meta: {}}'
}

# restore_cmd_opencode ENTRY_JSON
#   Build the shell command to resume an OpenCode session.
#   Prints the command string to stdout.
restore_cmd_opencode() {
    local entry="$1"
    local session_id
    session_id=$(jq -r '.session_id' <<< "$entry")

    printf 'opencode -s %s' "$(posix_quote "$session_id")"
}
