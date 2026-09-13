#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Shared Bash Logging Library                                                |
#|                                                                            |
#| Message shapes, level colouring, and session log file redirection for      |
#| chezmoi-managed scripts. Colour primitives live in term-colour.sh.         |
#|                                                                            |
#| Usage:                                                                     |
#|   source "${HOME}/.local/lib/bash-logging.sh"                             |
#|   setup_session_logging "$(basename "$0")" "topic"                        |
#|   bl_parse_help "$@"                                                       |
#|   log_step "What this script is doing"                                     |
#|   log_detail "What it just did"                                            |
#|                                                                            |
#| MESSAGE SHAPES — prefer these over hand-writing glyphs into info/warning.  |
#|   log_step    "› msg"    the script's scope; one per script, printed first  |
#|   log_detail  "╍ msg"    one outcome the script produced                    |
#|   log_warn    "╍ msg"    one problem, at warning level                      |
#|   log_cont    "  msg"    continuation of the line above (no glyph)          |
#|   log_ok      "✓ msg"    summary block: did it                              |
#|   log_skip    "⊘ msg"    summary block: skipped / unchanged                 |
#|   log_fail    "✗ msg"    summary block: failed (warning level)              |
#|   log_note    "→ msg"    summary block: where to look / what is next        |
#|                                                                            |
#| TOPIC TAGS — each script passes its topic as the second argument to         |
#|   setup_session_logging ("skills", "packages", "mcpproxy", …). Every        |
#|   structured line then carries a padded lowercase topic column:             |
#|     info packages    › Installing non-critical packages                    |
#|     info packages  ╍ Sudo detected — using it for the following commands    |
#|     info packages  ✓ Installed: 24                                          |
#|   The column width is BL_TOPIC_WIDTH (default 12). Captured subprocess      |
#|   output appended by run_quiet gets the same column with a "│" gutter, so   |
#|   the log reads as one column even through foreign output.                  |
#|                                                                            |
#| SECTION BOUNDARIES — one per script, same text in terminal and log:         |
#|     [HH:MM:SS] ──── install-060-reset-external-skills.sh ────               |
#|   chezmoi runs lifecycle scripts from <numeric-id>.<name>; the id is        |
#|   stripped. Nested calls (a script spawning another logging script inside   |
#|   its own tee) do not open a second section.                                |
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
#|   - Via chezmoi (marker at ~/.cache/dotfiles/chezmoi-session-current):    |
#|     uses session log shared across all chezmoi scripts                    |
#|   - Standalone: creates /tmp/<script>.<timestamp>.log                     |
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

# --- Topic tag ---------------------------------------------------------------
# Every structured line from a session script carries its topic in a padded
# lowercase column, so any line is attributable without reading back to the
# section boundary. BL_TOPIC_WIDTH is the fixed column width; topics longer
# than it push the glyph right rather than truncating.
BL_TOPIC_WIDTH="${BL_TOPIC_WIDTH:-12}"

_bl_topic_prefix() {
  [ -n "${BASH_LOGGING_TOPIC:-}" ] || return 0
  printf '%-*s ' "$BL_TOPIC_WIDTH" "$BASH_LOGGING_TOPIC"
}

# --- Levels -----------------------------------------------------------------
# Everything goes to stderr so a script's stdout stays usable for real output.
info() { color_print cyan "info $(_bl_topic_prefix)$*" >&2 ; }
warning() { color_print yellow "warning $(_bl_topic_prefix)$*" >&2 ; }
error() { color_print red "error $(_bl_topic_prefix)$*" >&2 ; }
fatal() { color_print red bold "fatal $(_bl_topic_prefix)$*" >&2 ; exit 1 ; }

# --- Message shapes ---------------------------------------------------------
# Namespaced because bash-logging.sh is sourced by ~30 scripts; short generic
# names (step, ok, note, fail) would be too easy to collide with.
log_step() { info "› $*" ; }
log_detail() { info "╍ $*" ; }
log_warn() { warning "╍ $*" ; }
log_warn_step() { warning "› $*" ; }
log_cont() { info "  $*" ; }
log_warn_cont() { warning "  $*" ; }
log_ok() { info "✓ $*" ; }
log_skip() { info "⊘ $*" ; }
log_fail() { warning "✗ $*" ; }
log_note() { info "→ $*" ; }

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
# On success, only NOTABLE output is appended to the session log (if active):
# package-manager no-ops and progress noise are dropped, real changes are kept.
# On failure, all captured stdout and stderr is shown on stderr (and reaches
# the session log through the tee).
# BL_LOG_ALL=1 disables the success filter (full output to the log).
run_quiet() {
  local output rc
  output=$(mktemp)
  "$@" > "$output" 2>&1 && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    if [ -n "${BASH_LOGGING_FILE:-}" ]; then
      if [ "${BL_LOG_ALL:-0}" = "1" ]; then
        cat "$output" >> "$BASH_LOGGING_FILE"
      else
        bl_log_notable < "$output"
      fi
    fi
  else
    cat "$output" >&2
  fi
  rm -f "$output"
  return "$rc"
}

# Drop steady-state and progress noise from a successful command's output,
# keeping evidence of real changes. Tuned for apt, mise and npm/mise resolver
# rows; anything unmatched is kept, so ordinary command output survives whole.
# Kept lines get the topic column with a "│" gutter so the log stays readable
# as one column through foreign output.
bl_log_notable() {
  [ -n "${BASH_LOGGING_FILE:-}" ] || return 0
  local prefix=""
  if [ -n "${BASH_LOGGING_TOPIC:-}" ]; then
    prefix=$(printf '     %-*s │ ' "$BL_TOPIC_WIDTH" "$BASH_LOGGING_TOPIC")
  fi
  awk -v prefix="$prefix" '
    /^The following packages were automatically installed/ { skip_list=1; next }
    skip_list && /^  / { next }
    skip_list { skip_list=0 }
    /^mise by @jdx/ { next }
    /^mise ⇢ / { next }
    /^mise █/ { next }
    /^mise ✓ / { next }
    /^mise is already up to date/ { next }
    /^mise all tools are installed/ { next }
    /ignored by minimum_release_age/ { next }
    /^mise Newer versions are available/ { skip_mise_notes=1; next }
    skip_mise_notes && /^  / { next }
    skip_mise_notes && /^…/ { next }
    skip_mise_notes && /^Run / { next }
    skip_mise_notes { skip_mise_notes=0 }
    /^Preparing to unpack / { next }
    /^User sessions running outdated binaries:/ { skip_needrestart=1; next }
    skip_needrestart && /^ / { next }
    skip_needrestart { skip_needrestart=0 }
    /\[[0-9]+\/[0-9]+\]/ { next }
    /resolving [0-9]+\/[0-9]+ pkgs/ { next }
    /is already the newest version/ { next }
    /^Reading package lists/ { next }
    /^Building dependency tree/ { next }
    /^Reading state information/ { next }
    /^\(Reading database/ { next }
    /^(Hit|Get|Ign):/ { next }
    /^Fetched / { next }
    /^nginx: the configuration file .* syntax is ok$/ { next }
    /^nginx: configuration file .* test is successful$/ { next }
    /^0 upgraded, 0 newly installed/ { next }
    /^Use .* to remove them/ { next }
    /^debconf: delaying package/ { next }
    /^Failed to retrieve available kernel versions/ { next }
    /^No services need to be restarted/ { next }
    /^No containers need to be restarted/ { next }
    /^No VM guests are running/ { next }
    /^[[:space:]]*$/ { next }
    { print prefix $0 }
  ' >> "$BASH_LOGGING_FILE"
}

# --- Session logging --------------------------------------------------------
# Strip ANSI colour so the log file is greppable. fflush() on every line means
# nothing is lost if the script exits before the subshell would have flushed —
# bash does not wait for process substitutions.
bl_strip_ansi() { awk '{ gsub(/\033\[[0-9;]*m/, ""); print; fflush() }'; }

_read_session_marker() {
  local marker_file="$1"
  local session_log

  [ -f "$marker_file" ] || return 1

  session_log=$(cat "$marker_file" 2>/dev/null | head -n 1 | tr -d '\n')
  if [ -z "$session_log" ] || [ ! -w "$(dirname "$session_log")" ]; then
    warning "Invalid log path in marker file: $session_log"
    return 1
  fi

  printf '%s\n' "$session_log"
}

_latest_session_log() {
  local dir="$1"
  local newest=""
  local candidate
  local nullglob_was_set=0

  [ -d "$dir" ] || return 1

  if shopt -q nullglob; then
    nullglob_was_set=1
  fi
  shopt -s nullglob

  for candidate in "$dir"/chezmoi-session.*.log; do
    if [ -z "$newest" ] || [ "$candidate" -nt "$newest" ]; then
      newest="$candidate"
    fi
  done

  if [ "$nullglob_was_set" -eq 0 ]; then
    shopt -u nullglob
  fi

  [ -n "$newest" ] && [ -w "$newest" ] || return 1
  printf '%s\n' "$newest"
}

setup_session_logging() {
  local script_name="${1:-unknown}"
  local topic="${2:-}"
  local timestamp
  local marker_file="${HOME}/.cache/dotfiles/chezmoi-session-current"
  local tmp_marker_file
  local tmpdir_marker_file="/tmp/.chezmoi-session-current"
  local darwin_tmpdir
  local darwin_marker_file
  local session_log=""

  timestamp=$(date +"%Y%m%d_%H%M%S")

  # Normalize TMPDIR
  local tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"
  tmp_marker_file="${tmpdir}/.chezmoi-session-current"

  # chezmoi executes lifecycle scripts from a temp path named
  # <numeric-id>.<script-name>; the id is per-run noise, not part of the name.
  case "$script_name" in
    [0-9]*.*) script_name="${script_name#*.}" ;;
  esac

  # A nested script may pass its own topic even though the parent owns the tee.
  if [ -n "$topic" ]; then
    export BASH_LOGGING_TOPIC="$topic"
  fi

  # Nested invocation (a parent script already owns the session tee and the
  # section boundary). Printing another boundary would duplicate the section
  # for one logical script.
  if [ "${BASH_LOGGING_ACTIVE:-0}" = "1" ] && [ -n "${BASH_LOGGING_FILE:-}" ]; then
    if [ "${DEBUG:-0}" = "1" ]; then
      set -x
    fi
    return 0
  fi

  # Determine log file location (in priority order)
  session_log=$(_read_session_marker "$marker_file" || true)

  if [ -z "$session_log" ]; then
    session_log=$(_read_session_marker "$tmp_marker_file" || true)
  fi

  if [ -z "$session_log" ]; then
    session_log=$(_read_session_marker "$tmpdir_marker_file" || true)
  fi

  if [ -z "$session_log" ]; then
    session_log=$(_latest_session_log "$tmpdir" || true)
  fi

  if [ -z "$session_log" ] && command -v getconf >/dev/null 2>&1; then
    darwin_tmpdir=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)
    darwin_tmpdir="${darwin_tmpdir%/}"
    if [ -n "$darwin_tmpdir" ]; then
      darwin_marker_file="${darwin_tmpdir}/.chezmoi-session-current"
      session_log=$(_read_session_marker "$darwin_marker_file" || true)
      if [ -z "$session_log" ]; then
        session_log=$(_latest_session_log "$darwin_tmpdir" || true)
      fi
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

  # Terminal keeps colour; the log copy has escapes stripped. The boundary is
  # printed AFTER the redirect so terminal and log show the same section line.
  exec > >(tee >(bl_strip_ansi >> "$session_log"))
  exec 2>&1

  bl_section "$script_name"

  # Enable debug tracing if requested
  if [ "${DEBUG:-0}" = "1" ]; then
    set -x
    info "DEBUG mode enabled - command tracing active"
  fi

  # Store log path for reference
  export BASH_LOGGING_FILE="$session_log"
  export BASH_LOGGING_ACTIVE=1
}

# Section boundary. Mirrors the hook's session header so terminal and log
# read the same: [HH:MM:SS] ──── script-name ────
bl_section() {
  color_print magenta dim "[$(date '+%H:%M:%S')] ──── $* ────" >&2
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
    color_print magenta dim "Session log: ${BASH_LOGGING_FILE}" >&2
  fi
  return 0
}
