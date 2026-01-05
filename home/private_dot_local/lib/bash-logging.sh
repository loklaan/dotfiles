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
#| When run via chezmoi (with marker file at /tmp/.chezmoi-session-current), |
#| all output is redirected to both terminal and the session log file.       |
#| When running standalone, output goes to terminal only.                    |
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
  if [ "$supported_colors" -gt 8 ]; then
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

  # Print startup message
  _print magenta dim "Script: $script_name"

  # Check for marker file first
  if [ -f "$marker_file" ]; then
    session_log=$(cat "$marker_file" 2>/dev/null | head -n 1 | tr -d '\n')

    # Validate that the log file path is reasonable
    if [ -n "$session_log" ] && [ -w "$(dirname "$session_log")" ]; then
      # Log script boundary marker
      echo "" >> "$session_log"
      echo "[$(date '+%H:%M:%S')] ===== $script_name =====" >> "$session_log"

      # Redirect all output to both terminal and session log
      exec > >(tee -a "$session_log")
      exec 2>&1

      return 0
    else
      warning "Invalid log path in marker file: $session_log"
    fi
  fi

  # Fallback to environment variable (backward compatibility)
  if [ -n "${CHEZMOI_SESSION_LOG:-}" ]; then
    session_log="$CHEZMOI_SESSION_LOG"

    # Log script boundary marker
    echo "" >> "$session_log"
    echo "[$(date '+%H:%M:%S')] ===== $script_name =====" >> "$session_log"

    # Redirect all output to both terminal and session log
    exec > >(tee -a "$session_log")
    exec 2>&1

    return 0
  fi

  # No session logging available - standalone mode
}
