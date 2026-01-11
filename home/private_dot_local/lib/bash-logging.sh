#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Shared Bash Logging Library                                               |
#|                                                                            |
#| Provides colored logging functions and session log file redirection       |
#| for chezmoi-managed scripts.                                               |
#|                                                                            |
#| Usage:                                                                     |
#|   source "${HOME}/.local/lib/bash-logging.sh"                             |
#|   setup_session_logging "$(basename "$0")"                                |
#|   info "Your message"                                                      |
#|                                                                            |
#| Logging behavior:                                                          |
#|   - Via chezmoi (marker at /tmp/.chezmoi-session-current): uses session   |
#|     log shared across all chezmoi scripts                                  |
#|   - Standalone: creates /tmp/<script>.<timestamp>.log                     |
#|                                                                            |
#| Environment Variables:                                                     |
#|   DEBUG=1              Enable command tracing (set -x) in logs            |
#|   CHEZMOI_SESSION_LOG  Override log file path (legacy)                    |
#|                                                                            |
#|----------------------------------------------------------------------------|

color_printf() {
  case "$1" in
    black) color="30" ;;
    red) color="31" ;;
    green) color="32" ;;
    yellow) color="33" ;;
    blue) color="34" ;;
    magenta) color="35" ;;
    cyan) color="36" ;;
    white) color="37" ;;
    *) echo "Unknown color: $1" >&2; return 1 ;;
  esac

  shift
  while [ "$#" -gt 1 ]; do
    case "$1" in
      bold) color="${color};1" ;;
      italic) color="${color};3" ;;
      underline) color="${color};4" ;;
      dim) color="${color};2" ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
    shift
  done

  supported_colors=$(tput colors 2>/dev/null)
  if [ -n "$supported_colors" ] && [ "$supported_colors" -gt 8 ]; then
    printf "\\033[${color}m%b\\033[0m" "$1"
  else
    printf "%b" "$1"
  fi
}

_printf() {
  color_printf "$@"
}

_print() {
  color_printf "$@"
  printf "\n"
}

# Logging functions just output - redirection handles file logging
info() { _print cyan "info $@" >&2 ; }
warning() { _print yellow "warning $@" >&2 ; }
error() { _print red "error $@" >&2 ; }
fatal() { _print red bold "fatal $@" >&2 ; exit 1 ; }
infof() { color_printf cyan "info $@" >&2 ; }
warningf() { color_printf yellow "warning $@" >&2 ; }
errorf() { color_printf red "error $@" >&2 ; }
fatalf() { color_printf red bold "fatal $@" >&2 ; exit 1 ; }

setup_session_logging() {
  local script_name="${1:-unknown}"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local marker_file="/tmp/.chezmoi-session-current"
  local session_log=""

  # Normalize TMPDIR
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"

  # Print startup message
  _print magenta dim "Script: $script_name"

  # Determine log file location (in priority order)
  if [ -f "$marker_file" ]; then
    # Chezmoi session marker exists - use shared session log
    session_log=$(cat "$marker_file" 2>/dev/null | head -n 1 | tr -d '\n')
    if [ -z "$session_log" ] || [ ! -w "$(dirname "$session_log")" ]; then
      warning "Invalid log path in marker file: $session_log"
      session_log=""
    fi
  fi

  if [ -z "$session_log" ] && [ -n "${CHEZMOI_SESSION_LOG:-}" ]; then
    # Fallback to environment variable (legacy)
    session_log="$CHEZMOI_SESSION_LOG"
  fi

  if [ -z "$session_log" ]; then
    # Standalone mode - create own log file
    session_log="${tmpdir}/${script_name}.${timestamp}.log"
  fi

  # Log script boundary marker
  echo "" >> "$session_log"
  echo "[$(date '+%H:%M:%S')] ===== $script_name =====" >> "$session_log"

  # Redirect all output to both terminal and session log
  exec > >(tee -a "$session_log")
  exec 2>&1

  # Enable debug tracing if requested
  if [ "${DEBUG:-0}" = "1" ]; then
    set -x
    info "DEBUG mode enabled - command tracing active"
  fi

  # Store log path for reference
  export BASH_LOGGING_FILE="$session_log"
}

print_log_path() {
  if [ -n "${BASH_LOGGING_FILE:-}" ]; then
    _print white dim "Log: $BASH_LOGGING_FILE"
  fi
}
