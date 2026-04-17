#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Code Agent Session Cleanup Hook                                             |
#|                                                                            |
#| Removes the session state file when a code agent session ends.             |
#|----------------------------------------------------------------------------|

[[ -z "${TMUX_PANE:-}" ]] && exit 0

STATE_DIR="${TMPDIR:-/tmp}/tmux-code-agent-sessions"
rm -f "$STATE_DIR/$TMUX_PANE"
