#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Resurrect Post-Restore Hook                                                |
#|                                                                            |
#| Resumes saved Claude Code sessions in their original tmux panes after     |
#| a tmux-resurrect restore. Called via @resurrect-hook-post-restore-all.    |
#|----------------------------------------------------------------------------|

set -euo pipefail

RESURRECT_DIR="${HOME}/.tmux/resurrect"
INPUT="$RESURRECT_DIR/claude-sessions.json"

[[ -f "$INPUT" ]] || exit 0

posix_quote() {
    printf "'"
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
    printf "'"
}

# Give panes time to initialise their shells
sleep 2

count=$(jq length "$INPUT")
for ((i = 0; i < count; i++)); do
    pane=$(jq -r ".[$i].pane" "$INPUT")
    session_id=$(jq -r ".[$i].session_id" "$INPUT")
    cwd=$(jq -r ".[$i].cwd" "$INPUT")
    model=$(jq -r ".[$i].model // \"\"" "$INPUT")
    flags=$(jq -r ".[$i].flags // \"\"" "$INPUT")

    # Verify the target pane exists
    tmux display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1 || continue

    # Only send to panes running a shell
    pane_cmd=$(tmux display-message -p -t "$pane" '#{pane_current_command}')
    case "$pane_cmd" in
        bash|zsh|fish|sh|dash|ksh) ;;
        *) continue ;;
    esac

    quoted_cwd=$(posix_quote "$cwd")
    quoted_sid=$(posix_quote "$session_id")

    # Build resume command with original invocation flags
    cmd="command otter claude-code"
    [[ -n "$model" ]] && cmd="$cmd --model $(posix_quote "$model")"
    [[ -n "$flags" ]] && cmd="$cmd $flags"
    cmd="$cmd --resume $quoted_sid"

    tmux send-keys -t "$pane" \
        "cd $quoted_cwd && $cmd" Enter
done
