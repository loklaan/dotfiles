#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

source "${HOME}/.local/lib/bash-logging.sh"
setup_session_logging "$(basename "$0")" "opencode2"

#/ Usage:
#/   run_after_install-071-opencode2.sh
#/
#/ Description:
#/   Installs and refreshes the OpenCode 2 CLI (`opencode2`) into a private npm
#/   prefix that only the ~/.local/bin/opencode2 wrapper reads.
#/
#/   OpenCode 2 is a SEPARATE binary from OpenCode 1 and is designed to run
#/   alongside it (https://opencode.ai/v2/docs/migrate-v1). Stable 2.x releases
#/   are published as @opencode/cli on the `latest` dist-tag. The earlier beta
#/   package (@opencode-ai/cli, 0.0.0-beta-*) is superseded: the Canva work
#/   plugin requires @opencode/plugin ^2.0.18 and refuses to load on a beta host,
#/   which also leaves a running service with stale Bedrock credentials. An
#/   existing beta install is migrated: its service is stopped, the session
#/   database is backed up to opencode2.db.pre-stable, and the package removed.
#/
#/   Installing into a private prefix (not a mise shim, not a global npm prefix)
#/   is load-bearing: mise shims sit AHEAD of ~/.local/bin on $PATH, so a shim
#/   named `opencode2` would shadow the wrapper that supplies the config/db
#/   isolation env vars, and an unwrapped opencode2 writes into OpenCode 1's
#/   config directory.
#/
#/   npm's postinstall is invoked explicitly rather than through `npm install`.
#/   Recent npm releases gate install scripts behind an approval prompt
#/   (`npm approve-scripts`), which would leave the platform binary unselected
#/   during a non-interactive apply. Running postinstall.mjs directly is
#/   deterministic and does not depend on npm's approval UX.
#/
#/   Best-effort throughout: a missing node or an unreachable registry logs and
#/   returns success, so `chezmoi apply` never fails on this.
#/
#/ Options:
#/   --help:      Display this help message
usage() { grep '^#/' "$0" | cut -c4-; }

readonly PACKAGE="@opencode/cli"
readonly DIST_TAG="latest"
readonly LEGACY_PACKAGE="@opencode-ai/cli"
readonly PREFIX="${HOME}/.local/share/opencode2"
readonly PACKAGE_JSON="${PREFIX}/lib/node_modules/${PACKAGE}/package.json"
readonly DATABASE="${HOME}/.local/share/opencode/opencode2.db"

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      *)
        usage
        fatal "Unknown argument: $1"
        ;;
    esac
  done
}

installed_version() {
  [ -f "$PACKAGE_JSON" ] || return 0
  node -e 'process.stdout.write(require(process.argv[1]).version ?? "")' \
    "$PACKAGE_JSON" 2>/dev/null || true
}

# The platform binary lives in an optionalDependency; postinstall.mjs copies it
# over the stub in bin/. Without it the wrapper execs a stub.
select_platform_binary() {
  local package_dir="${PREFIX}/lib/node_modules/${PACKAGE}"

  if [ ! -f "${package_dir}/postinstall.mjs" ]; then
    log_warn "postinstall.mjs missing — platform binary not selected (opencode2 may not run)"
    return 0
  fi

  if (cd "$package_dir" && node ./postinstall.mjs >/dev/null 2>&1); then
    log_detail "Selected platform binary for $(uname -s)/$(uname -m)"
  else
    log_warn "Platform binary postinstall failed — opencode2 may not run"
  fi
}

# Upgrading the binary does NOT replace OpenCode 2's shared background service:
# it outlives every client, so clients keep talking to the old version
# indefinitely (observed: service.json pinned 18707 while the binary was 18721).
# Stopping it is the fix — the next client launch starts a fresh one.
#
# Bounded and best-effort because this runs inside `chezmoi apply`. The pkill
# pattern is the full install path so a V1 `opencode` process can never match;
# it covers both the stable and the legacy beta package layouts.
stop_stale_service() {
  local pattern="${PREFIX}/lib/node_modules/@opencode(-ai)?/cli/bin/opencode2?\.exe"

  pgrep -f "$pattern" >/dev/null 2>&1 || return 0

  local binary="${PREFIX}/bin/opencode2"
  if [ -x "$binary" ]; then
    OPENCODE_CONFIG_DIR="${HOME}/.config/opencode2" \
      timeout 30 "$binary" service stop >/dev/null 2>&1 || true
    sleep 1
  fi

  # An unhealthy service (e.g. one whose database moved) cannot stop itself.
  if pgrep -f "$pattern" >/dev/null 2>&1; then
    pkill -f "$pattern" >/dev/null 2>&1 || true
    sleep 1
    pkill -9 -f "$pattern" >/dev/null 2>&1 || true
  fi

  log_detail "Stopped previous background service"
}

# One-time move off the beta package: stop its service before touching the
# database, keep a copy of the database, then remove the package so its
# `opencode2` bin link does not collide with the stable package's.
migrate_legacy_beta() {
  [ -d "${PREFIX}/lib/node_modules/${LEGACY_PACKAGE}" ] || return 0

  stop_stale_service

  if [ -f "$DATABASE" ] && [ ! -e "${DATABASE}.pre-stable" ]; then
    local suffix
    for suffix in "" "-wal" "-shm"; do
      [ -f "${DATABASE}${suffix}" ] && cp -p "${DATABASE}${suffix}" "${DATABASE}.pre-stable${suffix}"
    done
    log_detail "Backed up OpenCode 2 beta database to ${DATABASE}.pre-stable"
  fi

  npm uninstall --global --prefix "$PREFIX" --no-audit --no-fund --loglevel=error \
    "$LEGACY_PACKAGE" >/dev/null 2>&1 || log_warn "Could not remove ${LEGACY_PACKAGE}"
  log_detail "Removed legacy ${LEGACY_PACKAGE} beta"
}

main() {
  parse_args "$@"

  if ! command -v npm >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
    return 0
  fi

  log_step "Updating OpenCode 2 CLI"

  local available
  available=$(npm view "${PACKAGE}@${DIST_TAG}" version 2>/dev/null || true)

  if [ -z "$available" ]; then
    log_warn "Could not resolve ${PACKAGE}@${DIST_TAG} — offline?"
    return 0
  fi

  local current
  current=$(installed_version)

  if [ "$current" = "$available" ]; then
    log_detail "Unchanged: OpenCode 2 (${available})"
    return 0
  fi

  if [ -n "$current" ]; then
    log_detail "Updated OpenCode 2: ${current} → ${available}"
  else
    log_detail "Installed OpenCode 2: ${available}"
  fi

  mkdir -p "$PREFIX"
  migrate_legacy_beta

  if ! npm install --global --prefix "$PREFIX" --ignore-scripts \
    --no-audit --no-fund --loglevel=error "${PACKAGE}@${available}" >/dev/null 2>&1; then
    log_warn "npm install failed — leaving previous install in place"
    return 0
  fi

  select_platform_binary
  stop_stale_service

  log_detail "Installed wrapper at ~/.local/bin/opencode2 (config: ~/.config/opencode2)"
}

main "$@"
