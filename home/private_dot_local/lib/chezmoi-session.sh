#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Chezmoi Session Log                                                        |
#|                                                                            |
#| Creates and tears down the per-apply session log shared by the chezmoi     |
#| hooks (apply + update), and reused by df-task-update and install.sh.       |
#|                                                                            |
#| Usage (from a hook or wrapper):                                            |
#|   source "${HOME}/.local/lib/chezmoi-session.sh"                          |
#|   chezmoi_session_pre apply      # or: update                             |
#|   ...                                                                      |
#|   chezmoi_session_post                                                     |
#|                                                                            |
#| Reuse: when the caller already owns a session (CHEZMOI_SESSION_LOG, or     |
#| BASH_LOGGING_FILE from bash-logging), pre appends the section header to     |
#| that file and points the marker at it instead of creating a new log. The   |
#| caller is responsible for having announced the path.                       |
#|                                                                            |
#| The marker file (~/.cache/dotfiles/chezmoi-session-current) is the         |
#| contract with bash-logging.sh: each script reads it to find the log it     |
#| should tee into.                                                           |
#|----------------------------------------------------------------------------|

CHEZMOI_SESSION_MARKER_DIR="${HOME}/.cache/dotfiles"
CHEZMOI_SESSION_MARKER="${CHEZMOI_SESSION_MARKER_DIR}/chezmoi-session-current"

_cs_print_log_path() {
  printf '\033[2;35mSession log: %s\033[0m\n' "$1" >&2
}

_chezmoi_session_marker_age() {
  if [ "$(uname)" = "Darwin" ]; then
    echo $(($(date +%s) - $(stat -f %m "$1")))
  else
    echo $(($(date +%s) - $(stat -c %Y "$1")))
  fi
}

chezmoi_session_pre() {
  local label="${1:-session}"
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"

  local session_log=""
  local reused=0

  # Reuse an already-open session owned by the caller (df-task-update,
  # install.sh): its tee already captures output, so only a section header and
  # a marker pointing at the same file are needed.
  if [ -n "${CHEZMOI_SESSION_LOG:-}" ] && [ -w "${CHEZMOI_SESSION_LOG}" ]; then
    session_log="$CHEZMOI_SESSION_LOG"
    reused=1
  elif [ -n "${BASH_LOGGING_FILE:-}" ] && [ -w "${BASH_LOGGING_FILE}" ]; then
    session_log="$BASH_LOGGING_FILE"
    reused=1
  fi

  if [ "$reused" -eq 0 ]; then
    # Cleanup stale markers older than 24 hours
    if [ -f "$CHEZMOI_SESSION_MARKER" ]; then
      if [ "$(_chezmoi_session_marker_age "$CHEZMOI_SESSION_MARKER")" -gt 86400 ]; then
        rm -f "$CHEZMOI_SESSION_MARKER"
      fi
    fi

    session_log="${tmpdir}/chezmoi-session.$(date +%Y%m%d_%H%M%S).log"
    # Never truncate an existing session if two opens share a timestamp.
    if [ -e "$session_log" ]; then
      session_log="${tmpdir}/chezmoi-session.$(date +%Y%m%d_%H%M%S).$$.log"
    fi
    : > "$session_log"
  fi

  printf '[%s] ──── chezmoi %s ────\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$label" >> "$session_log"

  # Write marker file atomically
  mkdir -p "$CHEZMOI_SESSION_MARKER_DIR"
  printf '%s\n' "$session_log" > "${CHEZMOI_SESSION_MARKER}.$$"
  mv "${CHEZMOI_SESSION_MARKER}.$$" "$CHEZMOI_SESSION_MARKER"

  if [ "$reused" -eq 0 ]; then
    _cs_print_log_path "$session_log"
  fi
  return 0
}

chezmoi_session_post() {
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"

  rm -f "$CHEZMOI_SESSION_MARKER" "$tmpdir/.chezmoi-session-current" /tmp/.chezmoi-session-current 2>/dev/null || true
  return 0
}
