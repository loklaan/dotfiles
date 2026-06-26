#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Code Agent Session Cleanup Hook                                             |
#|                                                                            |
#| Removes the session state file when a code agent session ends.             |
#|----------------------------------------------------------------------------|

[[ -z "${TMUX_PANE:-}" ]] && exit 0

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=state-dir.sh
source "$DIR/state-dir.sh"
STATE_DIR="$(tcsa_state_dir)" || exit 0
rm -f "$STATE_DIR/$TMUX_PANE"
