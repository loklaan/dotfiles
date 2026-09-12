#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Shared Bash Logging Library                                                |
#|                                                                            |
#| Message shapes, level colouring, and session log file redirection for      |
#| chezmoi-managed scripts. Colour primitives live in term-colour.sh.         |
#|                                                                            |
#| Usage:                                                                     |
#|   source "${HOME}/.local/lib/bash-logging.sh"                             |
#|   setup_session_logging "$(basename "$0")"                                |
#|   bl_parse_help "$@"                                                       |
#|   log_step "What this script is doing"                                     |
#|   log_detail "What it just did"                                            |
#|                                                                            |
#| MESSAGE SHAPES — prefer these over hand-writing glyphs into info/warning.  |
#|   log_step    "▶ msg"    the script's scope; one per script, printed first  |
#|   log_detail  "╍ msg"    one outcome the script produced                    |
#|   log_warn    "╍ msg"    one problem, at warning level                      |
#|   log_cont    "  msg"    continuation of the line above (no glyph)          |
#|   log_ok      "  ✓ msg"  summary block: did it                             |
#|   log_skip    "  ⊘ msg"  summary block: skipped / unchanged                 |
#|   log_fail    "  ✗ msg"  summary block: failed (warning level)              |
#|   log_note    "  → msg"  summary block: where to look / what is next        |
#|                                                                            |
#| CONVENTIONS the shapes exist to enforce:                                    |
#|   - Every message starts with a capital letter and leads with a verb        |
#|     describing the outcome ("Started X", "Cleared Y"), never a bare         |
#|     lowercase tool name.                                                    |
#|   - Steady state prints nothing. Only transitions and problems get a line.  |
#|   - One line per outcome. Do not log an action and then log a confirmation  |
#|     of that same action; verify silently and warn only on failure.          |
#|                                                                            |
#| Logging behavior:                                                          |
#|   - Via chezmoi (marker at ~/.cache/dotfiles/chezmoi-session-current):     |
#|     uses the session log shared across all chezmoi scripts                 |
#|   - Standalone: creates a private ~/.cache/dotfiles/logs/<script> log      |
#|   - The terminal gets colour; the log file gets the same text with ANSI    |
#|     escapes stripped, so session logs stay greppable.                      |
#|                                                                            |
#| run_before_install SCRIPTS: they run before chezmoi materialises targets,   |
#|   so ~/.local/lib is the PREVIOUS apply's copy and a newly added helper     |
#|   here would abort their apply with exit 127. They must source this file    |
#|   from {{ .chezmoi.sourceDir }} instead. See                                |
#|   run_before_install-060-reset-external-skills.sh.tmpl.                     |
#|                                                                            |
#| Environment Variables:                                                     |
#|   DEBUG=1              Enable command tracing (set -x) in logs            |
#|   CHEZMOI_SESSION_LOG  Override log file path (legacy)                    |
#|                                                                            |
#|----------------------------------------------------------------------------|

# Colour primitives. Guarded so double-sourcing is free. `command -v` rather
# than the bash-only `declare -f`, so the guard survives a zsh caller.
#
# The existence check is load-bearing, NOT defensive noise: run_before_install
# scripts source this file BEFORE chezmoi has materialised any target, so on a
# fresh machine term-colour.sh may not be on disk yet. `source` of a missing
# file under `set -euo pipefail` would abort the whole apply, so fall back to
# plain text instead of taking a hard dependency.
if ! command -v color_printf >/dev/null 2>&1; then
  if [ -r "${HOME}/.local/lib/term-colour.sh" ]; then
    # shellcheck source=./term-colour.sh
    source "${HOME}/.local/lib/term-colour.sh"
  else
    color_printf() { [ "$#" -gt 1 ] && shift $(( $# - 1 )); printf "%b" "${1:-}"; }
    color_print() { color_printf "$@"; printf "\n"; }
  fi
fi

# --- Levels -----------------------------------------------------------------
# Everything goes to stderr so a script's stdout stays usable for real output.
info() { color_print cyan "info $*" >&2 ; }
warning() { color_print yellow "warning $*" >&2 ; }
error() { color_print red "error $*" >&2 ; }
fatal() { color_print red bold "fatal $*" >&2 ; exit 1 ; }

# --- Message shapes ---------------------------------------------------------
# Namespaced because bash-logging.sh is sourced by ~30 scripts; short generic
# names (step, ok, note, fail) would be too easy to collide with.
log_step() { info "▶ $*" ; }
log_detail() { info "╍ $*" ; }
log_warn() { warning "╍ $*" ; }
log_warn_step() { warning "▶ $*" ; }
log_cont() { info "  $*" ; }
log_warn_cont() { warning "  $*" ; }
log_ok() { info "  ✓ $*" ; }
log_skip() { info "  ⊘ $*" ; }
log_fail() { warning "  ✗ $*" ; }
log_note() { info "  → $*" ; }

# --- Argument parsing -------------------------------------------------------
# Default usage: the `#/` comment block at the top of the calling script.
bl_usage() { grep '^#/' "$0" | cut -c4-; }

# Handle the --help/unknown-argument boilerplate that every script repeated.
# Uses the script's own usage() when it defines one, else the `#/` block.
bl_parse_help() {
  local show_usage="bl_usage"
  if declare -f usage >/dev/null 2>&1; then
    show_usage="usage"
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help)
        "$show_usage"
        exit 0
        ;;
      *)
        "$show_usage"
        fatal "Unknown argument: $1"
        ;;
    esac
  done
}

# --- Command running --------------------------------------------------------
# Run a command quietly, showing output only on failure.
# On success, output is appended to the session log (if active) but hidden from terminal.
# On failure, all captured stdout and stderr is shown on stderr.
run_quiet() {
  local output rc
  output=$(mktemp)
  "$@" > "$output" 2>&1 && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    if [ -n "${BASH_LOGGING_FILE:-}" ]; then
      cat "$output" >> "$BASH_LOGGING_FILE"
    fi
  else
    cat "$output" >&2
  fi
  rm -f "$output"
  return "$rc"
}

# --- Session logging --------------------------------------------------------
# Strip ANSI colour so the log file is greppable. fflush() on every line means
# nothing is lost if the script exits before the subshell would have flushed —
# bash does not wait for process substitutions.
bl_strip_ansi() { awk '{ gsub(/\033\[[0-9;]*m/, ""); print; fflush() }'; }

_read_session_marker() {
  local marker_file="$1"
  local log_dir="$2"
  local session_log

  if [ ! -e "$marker_file" ] && [ ! -L "$marker_file" ]; then
    return 1
  fi

  if ! _bl_owned_regular_file "$marker_file"; then
    log_warn_cont "Ignoring session log marker at ${marker_file}; restore a regular file owned by the current user"
    return 1
  fi

  IFS= read -r session_log < "$marker_file" || true
  if ! _bl_trusted_log_file "$session_log" "$log_dir"; then
    log_warn_cont "Ignoring log destination from ${marker_file}; selecting a trusted log instead"
    return 1
  fi

  printf '%s\n' "$session_log"
}

_bl_path_uid() {
  stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1" 2>/dev/null
}

_bl_owned_regular_file() {
  local path="$1"
  local owner
  # Do not print the untrusted path: marker contents may contain credentials.
  if [ -L "$path" ]; then
    warning "Logging file rejected: symbolic links are not accepted"
    return 1
  fi
  if [ ! -f "$path" ]; then
    warning "Logging file rejected: expected an existing regular file"
    return 1
  fi
  if ! owner=$(_bl_path_uid "$path"); then
    warning "Logging file rejected: stat could not determine its owner"
    return 1
  fi
  if [ "$owner" != "$(id -u)" ]; then
    warning "Logging file rejected: owner UID ${owner} differs from current UID $(id -u)"
    return 1
  fi
}

_bl_owned_directory() {
  local path="$1"
  local owner
  if [ -L "$path" ]; then
    warning "Logging directory ${path} is a symbolic link; restore a user-owned directory"
    return 1
  fi
  if [ ! -d "$path" ]; then
    warning "Logging directory ${path} is not a directory; inspect it with ls -ld"
    return 1
  fi
  if ! owner=$(_bl_path_uid "$path"); then
    warning "Cannot determine owner of logging directory ${path}; inspect it with stat"
    return 1
  fi
  if [ "$owner" != "$(id -u)" ]; then
    warning "Logging directory ${path} belongs to UID ${owner}, not current UID $(id -u); restore current-user ownership"
    return 1
  fi
}

_bl_prepare_private_directory() {
  local path="$1"
  local old_umask

  old_umask=$(umask)
  umask 077
  if ! mkdir -p "$path"; then
    umask "$old_umask"
    return 1
  fi
  umask "$old_umask"

  _bl_owned_directory "$path" || return 1
  chmod 0700 "$path"
}

_bl_trusted_log_file() {
  local path="$1"
  local log_dir="$2"

  case "$path" in
    "$log_dir"/*) ;;
    *) warning "Logging destination rejected: expected a file under ${log_dir}"; return 1 ;;
  esac
  _bl_owned_regular_file "$path" || return 1
  if [ ! -w "$path" ]; then
    warning "Logging destination rejected: current user cannot write to the file; restore owner write permission"
    return 1
  fi
  chmod 0600 "$path"
}

_bl_create_private_log() {
  local log_dir="$1"
  local name="$2"
  local timestamp="$3"
  local old_umask
  local session_log

  name="${name##*/}"
  name="${name//[^[:alnum:]._-]/_}"
  old_umask=$(umask)
  umask 077
  session_log=$(mktemp "${log_dir}/${name}.${timestamp}.log.XXXXXX") || {
    umask "$old_umask"
    return 1
  }
  umask "$old_umask"
  _bl_trusted_log_file "$session_log" "$log_dir" || return 1
  printf '%s\n' "$session_log"
}

setup_session_logging() {
  local script_name="${1:-unknown}"
  local timestamp
  local state_dir="${HOME}/.cache/dotfiles"
  local log_dir="${HOME}/.cache/dotfiles/logs"
  local marker_file="${HOME}/.cache/dotfiles/chezmoi-session-current"
  local session_log=""

  timestamp=$(date +"%Y%m%d_%H%M%S")

  # Print startup message
  color_print magenta dim "Script: $script_name" >&2

  _bl_prepare_private_directory "$state_dir" || return 1
  _bl_prepare_private_directory "$log_dir" || return 1

  if [ "${BASH_LOGGING_ACTIVE:-0}" = "1" ] && [ -n "${BASH_LOGGING_FILE:-}" ]; then
    if _bl_trusted_log_file "$BASH_LOGGING_FILE" "$log_dir"; then
      session_log="$BASH_LOGGING_FILE"
      printf '\n[%s] ===== %s =====\n' "$(date '+%H:%M:%S')" "$script_name" >> "$session_log"
      if [ "${DEBUG:-0}" = "1" ]; then
        set -x
        info "DEBUG mode enabled - command tracing active"
      fi
      return 0
    fi
    log_warn_cont "Ignoring BASH_LOGGING_FILE; a trusted session log will be selected instead"
    unset BASH_LOGGING_FILE BASH_LOGGING_ACTIVE
  fi

  session_log=$(_read_session_marker "$marker_file" "$log_dir" || true)

  if [ -z "$session_log" ] && [ -n "${CHEZMOI_SESSION_LOG:-}" ]; then
    if _bl_trusted_log_file "$CHEZMOI_SESSION_LOG" "$log_dir"; then
      session_log="$CHEZMOI_SESSION_LOG"
    else
      log_warn_cont "Ignoring CHEZMOI_SESSION_LOG; a private standalone log will be used"
    fi
  fi

  if [ -z "$session_log" ]; then
    session_log=$(_bl_create_private_log "$log_dir" "$script_name" "$timestamp") || return 1
  fi

  # Log script boundary marker
  printf '\n[%s] ===== %s =====\n' "$(date '+%H:%M:%S')" "$script_name" >> "$session_log"

  # Terminal keeps colour; the log copy has escapes stripped.
  exec > >(tee >(bl_strip_ansi >> "$session_log"))
  exec 2>&1

  # Enable debug tracing if requested
  if [ "${DEBUG:-0}" = "1" ]; then
    set -x
    info "DEBUG mode enabled - command tracing active"
  fi

  # Store log path for reference
  export BASH_LOGGING_FILE="$session_log"
  export BASH_LOGGING_ACTIVE=1
}

# Tell the caller where the full output went, so a terse one-line failure is
# still traceable. install.sh installs this as an EXIT trap.
#
# NEVER let this fail. Under `set -e` a trap command that exits non-zero
# REPLACES the script's own exit status, so a broken print_log_path reports 127
# for a run that succeeded and 127 for a run that failed for an unrelated
# reason — identically. That is not hypothetical: this function was documented
# here but never actually defined, so every `install.sh` failure surfaced to
# `coder dotfiles` as a bare `exit status 127`. It masked a chezmoi template
# abort that had silently left every Pitchfork daemon dead since boot, because
# daemon startup is a side effect of a successful apply.
print_log_path() {
  if [ -n "${BASH_LOGGING_FILE:-}" ] && [ -f "${BASH_LOGGING_FILE}" ]; then
    color_print magenta dim "Log: ${BASH_LOGGING_FILE}" >&2
  fi
  return 0
}
