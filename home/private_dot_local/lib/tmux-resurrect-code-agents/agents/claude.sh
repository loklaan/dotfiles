#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Claude Code Agent Module                                                    |
#|                                                                            |
#| Provides detect and restore_cmd functions for Claude Code sessions.        |
#| Sourced by save.sh and restore.sh — do not execute directly.               |
#|----------------------------------------------------------------------------|

# detect_claude PANE_ID CWD
#   Check hook-tracked state for a Claude Code session.
#   Prints JSON entry on success, returns 1 if no session found.
detect_claude() {
    local pane_id="$1" cwd="$2"
    local state_file="${STATE_DIR:-}/$pane_id"

    [[ -n "${STATE_DIR:-}" ]] || return 1
    [[ -f "$state_file" ]] || return 1

    # Read state file (JSON with agent field from track.sh)
    local agent
    agent=$(jq -r '.agent // empty' "$state_file" 2>/dev/null) || return 1
    [[ "$agent" == "claude" ]] || return 1

    local session_id model flags
    session_id=$(jq -r '.session_id // empty' "$state_file")
    [[ -n "$session_id" ]] || return 1
    model=$(jq -r '.model // ""' "$state_file")
    flags=$(jq -r '.flags // ""' "$state_file")

    jq -n \
        --arg pane "$pane_id" \
        --arg agent "claude" \
        --arg sid "$session_id" \
        --arg cwd "$cwd" \
        --arg model "$model" \
        --arg flags "$flags" \
        '{pane: $pane, agent: $agent, session_id: $sid, cwd: $cwd, meta: {model: $model, flags: $flags}}'
}

# restore_cmd_claude ENTRY_JSON
#   Build the shell command to resume a Claude Code session.
#   Prints the command string to stdout.
restore_cmd_claude() {
    local entry="$1"
    local session_id model flags

    session_id=$(jq -r '.session_id' <<< "$entry")
    model=$(jq -r '.meta.model // ""' <<< "$entry")
    flags=$(jq -r '.meta.flags // ""' <<< "$entry")

    local cmd="command claude"
    [[ -n "$model" ]] && cmd="$cmd --model $(posix_quote "$model")"

    # SECURITY: `flags` is attacker-influencable — it originates from a ps-scan
    # written to a per-pane state file, and the command this builds is later
    # sourced from a drop file. Concatenating it raw is shell-command
    # injection. Tokenize it, allow-list the flag NAME, and posix_quote any
    # value. Unknown names are warned-and-skipped (never silently dropped, and
    # the --permission-mode value is never enumerated) so a future permission
    # mode keeps restoring while metacharacters can never reach the shell.
    if [[ -n "$flags" ]]; then
        local -a _toks=()
        read -ra _toks <<< "$flags" || true
        local _i=0 _n=${#_toks[@]} _t
        while (( _i < _n )); do
            _t="${_toks[_i]}"
            case "$_t" in
                --dangerously-skip-permissions)
                    cmd="$cmd --dangerously-skip-permissions"
                    ;;
                --permission-mode=*)
                    cmd="$cmd --permission-mode=$(posix_quote "${_t#*=}")"
                    ;;
                --permission-mode)
                    if (( _i + 1 < _n )); then
                        _i=$(( _i + 1 ))
                        cmd="$cmd --permission-mode $(posix_quote "${_toks[_i]}")"
                    else
                        printf 'restore_cmd_claude: --permission-mode given without a value; skipping\n' >&2
                    fi
                    ;;
                *)
                    printf 'restore_cmd_claude: ignoring unrecognised restore flag %s\n' "$_t" >&2
                    ;;
            esac
            _i=$(( _i + 1 ))
        done
    fi

    cmd="$cmd --resume $(posix_quote "$session_id")"

    printf '%s' "$cmd"
}
