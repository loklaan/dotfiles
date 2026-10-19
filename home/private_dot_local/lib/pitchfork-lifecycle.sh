#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Pitchfork Daemon Lifecycle                                                 |
#|                                                                            |
#| Helpers for run_onchange_after_install-056-pitchfork-daemons, which only    |
#| converges daemon state when the rendered Pitchfork config or a gate flips.  |
#| Running daemons restart themselves through `watch` (see                     |
#| private_dot_config/pitchfork/config.toml.tmpl). The script only renders     |
#| when pitchfork is on PATH, so these call `pitchfork` directly. Failures     |
#| exit non-zero so the run_onchange script is retried next apply.             |
#|                                                                            |
#| Requires bash-logging.sh to be sourced first (log_detail / log_warn).       |
#|----------------------------------------------------------------------------|

# Register the login service against [settings.boot] executable. `boot enable`
# rewrites an existing entry, which is what moves a service still pointing at
# an old pitchfork version. A container/Coder workspace has no user service
# manager ("Failed to connect to bus"); boot persistence does not apply there.
pf_boot_enable() {
  local boot_err
  if boot_err=$(pitchfork boot enable 2>&1); then
    log_detail "Registered Pitchfork to start at login"
    return 0
  fi
  case "$boot_err" in
    *"connect to bus"*|*"No medium found"*) return 0 ;;
  esac
  log_warn "Could not register Pitchfork to start at login"
  log_warn_cont "$boot_err"
  return 1
}

# Restart the supervisor when it runs an older pitchfork than the CLI (after a
# mise bump). Daemons with boot_start come back with it. The CLI reports the
# mismatch on stderr.
pf_restart_stale_supervisor() {
  if pitchfork list 2>&1 >/dev/null | grep -q 'differs from supervisor version'; then
    if pitchfork supervisor start --force >/dev/null 2>&1; then
      log_detail "Restarted the Pitchfork supervisor on the current version"
    else
      log_warn "Could not restart the stale Pitchfork supervisor"
      log_warn_cont "Run: pitchfork supervisor start --force"
    fi
  fi
}

# Start a daemon. A no-op when it is already running; auto-starts the
# supervisor.
pf_start() {
  local daemon="$1"
  if ! pitchfork start --quiet "$daemon" >/dev/null 2>&1; then
    log_warn "Failed to start ${daemon} — check: pitchfork logs ${daemon}"
    return 1
  fi
  log_detail "Ensured ${daemon} is running"
}

# Stop a daemon that a gate turned off. Pitchfork exits non-zero for a daemon
# that is no longer in its config, which is the normal case here, so this is
# best-effort and quiet.
pf_stop() {
  pitchfork stop "$1" >/dev/null 2>&1 || true
}
