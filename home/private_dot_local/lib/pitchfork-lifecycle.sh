#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Pitchfork Daemon Lifecycle                                                 |
#|                                                                            |
#| One implementation of "resolve pitchfork, restart a daemon, confirm it took, |
#| probe its port" for the chezmoi scripts that manage Pitchfork daemons:      |
#| df-drift-notify, df-opencode-serve, df-orca-server, df-code-server,        |
#| df-mcpproxy.                                                               |
#|                                                                            |
#| Usage:                                                                     |
#|   source "${HOME}/.local/lib/bash-logging.sh"                             |
#|   source "${HOME}/.local/lib/pitchfork-lifecycle.sh"                      |
#|   pf_resolve || return 0        # sets PITCHFORK_BIN, warns if absent      |
#|   pf_restart df-opencode-serve                                             |
#|   pf_probe_http 4096 "opencode server"                                     |
#|                                                                            |
#| WHY this exists: verify_pitchfork_installed was byte-identical in three     |
#| scripts with a fourth renamed copy in a fifth, so every wording or          |
#| behaviour fix had to be made four times — and reliably was not, which is    |
#| how the log output drifted apart in the first place.                        |
#|                                                                            |
#| STREAM QUIRK, the reason a wrapper earns its keep: pitchfork does NOT put   |
#| all output on one stream.                                                   |
#|   `boot status`  -> STDERR   ("pitchfork Boot start is enabled")            |
#|   `list`         -> STDOUT   (daemon rows) + STDERR (version WARN)          |
#|   `daemons`      -> STDOUT                                                  |
#| A `boot status 2>/dev/null | grep` therefore matches NOTHING, silently, and |
#| that bug shipped: every apply re-enabled boot start and logged it as a      |
#| change. Capture the right stream here, once.                                |
#|                                                                            |
#| Requires bash-logging.sh to be sourced first (log_detail / log_warn).       |
#|----------------------------------------------------------------------------|

PITCHFORK_BIN="${PITCHFORK_BIN:-}"

# Resolve the pitchfork binary into PITCHFORK_BIN: PATH first, then mise (which
# is where it actually lives on a fresh box, before shims are on PATH).
# Returns 1 and warns when it cannot be found, so callers can skip cleanly.
pf_resolve() {
  if [ -n "$PITCHFORK_BIN" ] && [ -x "$PITCHFORK_BIN" ]; then
    return 0
  fi

  if command -v pitchfork >/dev/null 2>&1; then
    PITCHFORK_BIN=$(command -v pitchfork)
  elif command -v mise >/dev/null 2>&1; then
    PITCHFORK_BIN=$(mise which pitchfork 2>/dev/null || echo "")
  fi

  if [ -z "$PITCHFORK_BIN" ] || [ ! -x "$PITCHFORK_BIN" ]; then
    log_warn "Missing pitchfork — install with: mise install"
    return 1
  fi
}

# Stop a daemon. Idempotent and quiet: stopping an already-stopped daemon is
# not an event. Callers that want to report the stop should log it themselves,
# because "opted out, so I stopped it" reads differently from "restarting".
pf_stop() {
  local daemon="$1"
  "$PITCHFORK_BIN" stop "$daemon" >/dev/null 2>&1 || true
}

# Start a daemon, then confirm the supervisor actually took it. Reports the
# start with an overridable message (a scheduled daemon is "Registered ... to
# run daily at 09:30", not "Started"); stays silent on a successful confirm and
# warns only when the supervisor does not report the daemon.
pf_start() {
  local daemon="$1"
  local message="${2:-Started ${daemon} daemon}"

  if ! "$PITCHFORK_BIN" start --quiet "$daemon" >/dev/null 2>&1; then
    log_warn "Failed to start ${daemon} — check: pitchfork logs ${daemon}"
    return 1
  fi
  log_detail "$message"

  sleep 2
  if ! pf_is_registered "$daemon"; then
    log_warn "Pitchfork did not report ${daemon} — check: pitchfork logs ${daemon}"
    return 1
  fi
}

# Restart so config changes are picked up. Separate pf_stop / pf_start remain
# available for callers that must do work between the two (063 reaps orphaned
# processes holding the daemon's port before it can bind).
pf_restart() {
  local daemon="$1"
  pf_stop "$daemon"
  pf_start "$@"
}

# Is the daemon known to the supervisor? Rows come from stdout; the version WARN
# on stderr is deliberately discarded so it cannot false-positive the grep.
pf_is_registered() {
  local daemon="$1"
  "$PITCHFORK_BIN" list 2>/dev/null | grep -q "$daemon"
}

# Ensure the supervisor is up, and boot-enabled so scheduled (cron) daemons
# survive a reboot. Only reports the transition — already-enabled is the steady
# state, not news.
pf_ensure_supervisor() {
  "$PITCHFORK_BIN" supervisor start >/dev/null 2>&1 || true

  # `boot status` answers on STDERR; 2>&1 is load-bearing (see header).
  if "$PITCHFORK_BIN" boot status 2>&1 | grep -qi 'is enabled'; then
    return 0
  fi

  if "$PITCHFORK_BIN" boot enable >/dev/null 2>&1; then
    log_detail "Enabled Pitchfork to start at boot"
  else
    log_warn "Could not enable Pitchfork to start at boot — daemons may not survive reboot"
  fi
}

# A supervisor left running from an older Pitchfork keeps serving after mise
# upgrades the CLI, and a pre-2.19.0 supervisor ignores `cron` outright — so a
# scheduled daemon registers fine and simply never fires. Pitchfork reports the
# mismatch as a WARN on stderr of any command; relay it with the remedy rather
# than restarting the supervisor from here, which would kill live daemons.
pf_warn_if_supervisor_stale() {
  if "$PITCHFORK_BIN" list 2>&1 >/dev/null | grep -q 'differs from supervisor version'; then
    log_warn "Pitchfork supervisor is older than the CLI — scheduled daemons are likely ignored"
    log_warn_cont "Restart it with: pitchfork supervisor start --force"
    return 1
  fi
}

# Is the installed pitchfork new enough for the `cron` daemon field? Releases
# before 2.19.0 accept it in config and silently never fire. Quiet on success.
pf_verify_cron_capable() {
  local min="2.19.0"
  local ver lowest
  ver=$("$PITCHFORK_BIN" --version 2>/dev/null | awk '{print $NF}')
  lowest=$(printf '%s\n%s\n' "$ver" "$min" | sort -V | head -1)

  if [ "$lowest" != "$min" ] && [ "$ver" != "$min" ]; then
    log_warn "Pitchfork ${ver} predates cron support (needs >= ${min});"
    log_warn_cont "scheduled daemons will NOT fire. Run: mise install"
    return 1
  fi
}

# HTTP health probe against a daemon's loopback port.
pf_probe_http() {
  local port="$1"
  local label="$2"

  if curl -sf "http://127.0.0.1:${port}/" -o /dev/null 2>/dev/null; then
    log_detail "Health probe OK — ${label} is responding"
    return 0
  fi
  log_warn "Health probe failed — ${label} not responding at http://127.0.0.1:${port}/"
  return 1
}
