#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| macOS Desktop App Lifecycle                                                |
#|                                                                            |
#| Shared opt-out reconciliation for retained desktop applications.           |
#| Requires bash-logging.sh to be sourced first.                              |
#|----------------------------------------------------------------------------|

dal_disable_app() {
  local app="$1"
  local slug="$2"
  local failed=0
  local plist label command_error

  if pgrep -x "$app" >/dev/null 2>&1; then
    if ! command_error=$(osascript -e "tell application \"${app}\" to quit" 2>&1); then
      log_warn "macOS could not quit ${app}.app: ${command_error:-no diagnostic output}"
      log_warn_cont "Inspect: pgrep -x \"${app}\""
      failed=1
    elif pgrep -x "$app" >/dev/null 2>&1; then
      log_warn "${app}.app remains running after macOS accepted the quit request"
      log_warn_cont "Inspect: pgrep -x \"${app}\""
      failed=1
    else
      log_detail "Quit ${app}.app"
    fi
  fi

  if ! command_error=$(osascript -e "tell application \"System Events\" to delete every login item whose name is \"${app}\"" 2>&1); then
    log_warn "System Events could not remove the ${app}.app login item: ${command_error:-no diagnostic output}"
    log_warn_cont "Inspect login items: osascript -e 'tell application \"System Events\" to get the name of every login item'"
    failed=1
  fi

  shopt -s nullglob nocaseglob
  for plist in "${HOME}/Library/LaunchAgents/"*"${slug}"*.plist; do
    launchctl bootout "gui/${UID}" "$plist" >/dev/null 2>&1 || true
    if ! label=$(plutil -extract Label raw -o - "$plist" 2>&1); then
      log_warn "plutil could not read the LaunchAgent label from ${plist}: ${label:-no diagnostic output}"
      log_warn_cont "Inspect: plutil -lint \"${plist}\""
      failed=1
      continue
    fi
    if [ -z "$label" ]; then
      log_warn "LaunchAgent ${plist} has an empty Label value"
      log_warn_cont "Inspect: plutil -extract Label raw -o - \"${plist}\""
      failed=1
      continue
    fi
    if command_error=$(launchctl disable "gui/${UID}/${label}" 2>&1); then
      log_detail "Disabled ${app}.app LaunchAgent ${label}"
    else
      log_warn "launchctl could not disable ${app}.app LaunchAgent ${label}: ${command_error:-no diagnostic output}"
      log_warn_cont "Inspect: launchctl print-disabled gui/${UID}"
      failed=1
    fi
  done
  shopt -u nullglob nocaseglob

  return "$failed"
}
