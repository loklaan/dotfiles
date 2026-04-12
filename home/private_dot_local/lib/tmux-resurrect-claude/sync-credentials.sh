#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Credentials Symlink Repair                                                 |
#|                                                                            |
#| Detects and repairs the Otter .credentials.json symlink after atomic      |
#| writes replace it with a regular file. Runs as a SessionStart hook.       |
#|----------------------------------------------------------------------------|

set -euo pipefail

CLAUDE_CREDS="${HOME}/.claude/.credentials.json"
OTTER_CREDS="${HOME}/Library/Application Support/Otter/claude-code-user/.credentials.json"

# Only act on macOS where the Otter directory exists
[[ -d "${OTTER_CREDS%/*}" ]] || exit 0

# If the Otter credentials is already a symlink, nothing to do
[[ -L "$OTTER_CREDS" ]] && exit 0

# The symlink was replaced by an atomic write — Otter has the fresher tokens.
# Sync the newer file to primary, then restore the symlink.
if [[ -f "$OTTER_CREDS" ]]; then
    [[ "$OTTER_CREDS" -nt "$CLAUDE_CREDS" ]] && cp "$OTTER_CREDS" "$CLAUDE_CREDS"
    rm "$OTTER_CREDS"
    ln -s "$CLAUDE_CREDS" "$OTTER_CREDS"
fi
