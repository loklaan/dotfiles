#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Claude Code SessionEnd Hook                                                |
#|                                                                            |
#| Removes the session state file when a Claude Code session ends.            |
#|----------------------------------------------------------------------------|

[[ -z "${TMUX_PANE:-}" ]] && exit 0

STATE_DIR="${TMPDIR:-/tmp}/tmux-claude-sessions"
rm -f "$STATE_DIR/$TMUX_PANE"
