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
#| caller is responsible for having announced the path. Only files under the  |
#| private log directory are trusted.                                         |
#|                                                                            |
#| The marker file (~/.cache/dotfiles/chezmoi-session-current) is the         |
#| contract with bash-logging.sh: each script reads it to find the log it     |
#| should tee into.                                                           |
#|----------------------------------------------------------------------------|

CHEZMOI_SESSION_MARKER_DIR="${HOME}/.cache/dotfiles"
CHEZMOI_SESSION_LOG_DIR="${CHEZMOI_SESSION_MARKER_DIR}/logs"
CHEZMOI_SESSION_MARKER="${CHEZMOI_SESSION_MARKER_DIR}/chezmoi-session-current"

_cs_print_log_path() {
  printf '\033[2;35mSession log: %s\033[0m\n' "$1" >&2
}

_cs_path_uid() {
  stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1" 2>/dev/null
}

_cs_trusted_directory() {
  local path="$1"
  local owner

  if [ -L "$path" ]; then
    printf 'Cannot use session log directory %s: symbolic links are not accepted\n' "$path" >&2
    return 1
  fi
  if [ ! -d "$path" ]; then
    printf 'Cannot use session log directory %s: not a directory\n' "$path" >&2
    return 1
  fi
  if ! owner=$(_cs_path_uid "$path"); then
    printf 'Cannot determine owner of session log directory %s\n' "$path" >&2
    return 1
  fi
  if [ "$owner" != "$(id -u)" ]; then
    printf 'Cannot use session log directory %s: owner UID %s differs from current UID %s\n' \
      "$path" "$owner" "$(id -u)" >&2
    return 1
  fi
}

_cs_prepare_directory() {
  local path="$1"
  local old_umask

  old_umask=$(umask)
  umask 077
  if ! mkdir -p "$path"; then
    umask "$old_umask"
    return 1
  fi
  umask "$old_umask"

  _cs_trusted_directory "$path" || return 1
  chmod 0700 "$path"
}

_cs_trusted_log_file() {
  local path="$1"
  local owner

  case "$path" in
    "${CHEZMOI_SESSION_LOG_DIR}"/*) ;;
    *) printf 'Ignoring session log %s: not under %s\n' "$path" "$CHEZMOI_SESSION_LOG_DIR" >&2; return 1 ;;
  esac
  if [ -L "$path" ] || [ ! -f "$path" ]; then
    printf 'Ignoring session log %s: expected a regular file\n' "$path" >&2
    return 1
  fi
  if ! owner=$(_cs_path_uid "$path"); then
    printf 'Ignoring session log %s: cannot determine owner\n' "$path" >&2
    return 1
  fi
  if [ "$owner" != "$(id -u)" ] || [ ! -w "$path" ]; then
    printf 'Ignoring session log %s: not owned or writable by the current user\n' "$path" >&2
    return 1
  fi
  chmod 0600 "$path"
}

_cs_create_log() {
  local session_log

  session_log=$(mktemp "${CHEZMOI_SESSION_LOG_DIR}/chezmoi-session.$(date +%Y%m%d_%H%M%S).log.XXXXXX") || return 1
  _cs_trusted_log_file "$session_log" || return 1
  printf '%s\n' "$session_log"
}

chezmoi_session_pre() {
  local label="${1:-session}"
  local session_log=""
  local reused=0

  _cs_prepare_directory "$CHEZMOI_SESSION_MARKER_DIR" || return 1
  _cs_prepare_directory "$CHEZMOI_SESSION_LOG_DIR" || return 1

  # Reuse an already-open session owned by the caller (df-task-update,
  # install.sh), but only a trusted file under the private log directory.
  if [ -n "${CHEZMOI_SESSION_LOG:-}" ] && _cs_trusted_log_file "$CHEZMOI_SESSION_LOG"; then
    session_log="$CHEZMOI_SESSION_LOG"
    reused=1
  elif [ -n "${BASH_LOGGING_FILE:-}" ] && _cs_trusted_log_file "$BASH_LOGGING_FILE"; then
    session_log="$BASH_LOGGING_FILE"
    reused=1
  fi

  if [ "$reused" -eq 0 ]; then
    session_log=$(_cs_create_log) || return 1
  fi

  printf '[%s] ──── chezmoi %s ────\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$label" >> "$session_log"

  # Write the marker through a private, uniquely created file.
  marker_tmp=$(mktemp "${CHEZMOI_SESSION_MARKER_DIR}/.chezmoi-session-current.XXXXXX")
  printf '%s\n' "$session_log" > "$marker_tmp"
  chmod 0600 "$marker_tmp"
  mv "$marker_tmp" "$CHEZMOI_SESSION_MARKER"
  chmod 0600 "$CHEZMOI_SESSION_MARKER"

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

#|----------------------------------------------------------------------------|
#| Shared body of the apply.pre and update.pre hooks: open the session, fix
#| known permission drift, then run the preflight checks (after the session
#| exists, so their warnings land in the session log).
#|
#| Usage: chezmoi_hook_pre apply|update
#|
chezmoi_hook_pre() {
  chezmoi_session_pre "$1"

  # macOS: normalize directory permissions that drift from chezmoi's expected
  # modes. launchd resets ~/Library/LaunchAgents to 0744 after plist loading,
  # but chezmoi expects 0755. Normalizing here prevents the apply-time prompt.
  # See: https://github.com/twpayne/chezmoi/issues/769
  if [ "$(uname)" = "Darwin" ]; then
    chmod 755 "${HOME}/Library/LaunchAgents" 2>/dev/null || true
  fi

  # Pre-flight checks for required tools
  local preflight="${HOME}/.local/lib/chezmoi-preflight.sh"
  # shellcheck source=./chezmoi-preflight.sh
  [ -f "$preflight" ] && source "$preflight" || true
}
