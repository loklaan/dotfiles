#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| OpenCode Agent Module                                                       |
#|                                                                            |
#| Provides detect and restore_cmd functions for OpenCode sessions.           |
#| Sourced by save.sh and restore.sh — do not execute directly.               |
#|----------------------------------------------------------------------------|

# detect_opencode PANE_ID CWD
#   Read the hook-tracked state written by the OpenCode plugin.
#   Prints JSON entry on success, returns 1 if no session found.
#
#   Callers MUST have already accepted the claim via tcsa_claim_is_live. There is
#   deliberately no secondary detection path: a session id recovered by querying
#   OpenCode's database would prove the session EXISTS, never that this pane is
#   still hosting it, and an unverifiable claim is exactly the defect the
#   LIVENESS CONTRACT exists to prevent.
detect_opencode() {
    local pane_id="$1" cwd="$2"
    local state_file="${STATE_DIR:-}/$pane_id"

    [[ -n "${STATE_DIR:-}" ]] || return 1
    [[ -f "$state_file" ]] || return 1

    local agent
    agent=$(jq -r '.agent // empty' "$state_file" 2>/dev/null) || return 1
    [[ "$agent" == "opencode" ]] || return 1

    local session_id
    session_id=$(jq -r '.session_id // empty' "$state_file")
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
