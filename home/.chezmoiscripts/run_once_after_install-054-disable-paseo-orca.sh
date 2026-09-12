#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

source "${HOME}/.local/lib/bash-logging.sh"
setup_session_logging "$(basename "$0")"

#/ Usage:
#/   run_once_after_install-054-disable-paseo-orca.sh
#/
#/ Description:
#/   One-time migration that persists the security opt-out for Paseo and Orca
#/   in chezmoi's machine-local TOML data. Runtime lifecycle scripts read these
#/   values after this migration, so a stale template rendered from historical
#/   true values cannot restart either integration later in the same apply.
#/
#/ Options:
#/   --help:      Display this help message

main() {
  bl_parse_help "$@"

  local config="${HOME}/.config/chezmoi/chezmoi.toml"
  local temporary
  local paseo_value orca_value

  log_step "paseo and orca security opt-out migration"

  if [ ! -f "$config" ]; then
    log_warn "Cannot persist integration opt-outs because ${config} does not exist"
    log_warn_cont "Inspect: ls -ld \"$(dirname "$config")\""
    return 1
  fi
  if ! command -v yq >/dev/null 2>&1; then
    log_warn "Cannot persist integration opt-outs because yq is not on PATH"
    log_warn_cont "Inspect: command -v yq"
    return 1
  fi

  if ! paseo_value=$(yq -p=toml -o=json -r '.data.paseoDaemon // false' "$config" 2>/dev/null); then
    log_warn "Integration opt-out migration aborted because yq could not read data.paseoDaemon from ${config}; config is unchanged"
    log_warn_cont "Inspect: yq -p=toml -o=json -r '.data.paseoDaemon // false' \"${config}\""
    return 1
  fi
  if ! orca_value=$(yq -p=toml -o=json -r '.data.orcaServer // false' "$config" 2>/dev/null); then
    log_warn "Integration opt-out migration aborted because yq could not read data.orcaServer from ${config}; config is unchanged"
    log_warn_cont "Inspect: yq -p=toml -o=json -r '.data.orcaServer // false' \"${config}\""
    return 1
  fi

  if [ "$paseo_value" == false ] && [ "$orca_value" == false ]; then
    return 0
  fi

  temporary=$(mktemp "${config}.XXXXXX")
  trap 'rm -f "${temporary:-}"' EXIT
  cp -p "$config" "$temporary"
  if ! yq -p=toml -o=toml -i '.data.paseoDaemon = false | .data.orcaServer = false' "$temporary" 2>/dev/null; then
    log_warn "Integration opt-out migration aborted because yq could not update the temporary config copy; original config is unchanged"
    log_warn_cont "Reproduce the transform locally without writing config: yq -p=toml -o=toml '.data.paseoDaemon = false | .data.orcaServer = false' \"${config}\" >/dev/null"
    return 1
  fi

  if ! paseo_value=$(yq -p=toml -o=json -r '.data.paseoDaemon' "$temporary" 2>/dev/null); then
    log_warn "Integration opt-out migration aborted because yq could not validate updated data.paseoDaemon; original config is unchanged"
    log_warn_cont "Check transformed flags (expect true): yq -p=toml -o=json '(.data.paseoDaemon = false | .data.orcaServer = false) | .data.paseoDaemon == false' \"${config}\""
    return 1
  fi
  if [ "$paseo_value" != false ]; then
    log_warn "Integration opt-out migration aborted because updated data.paseoDaemon is not false; original config is unchanged"
    log_warn_cont "Check transformed flags (expect true): yq -p=toml -o=json '(.data.paseoDaemon = false | .data.orcaServer = false) | .data.paseoDaemon == false' \"${config}\""
    return 1
  fi
  if ! orca_value=$(yq -p=toml -o=json -r '.data.orcaServer' "$temporary" 2>/dev/null); then
    log_warn "Integration opt-out migration aborted because yq could not validate updated data.orcaServer; original config is unchanged"
    log_warn_cont "Check transformed flags (expect true): yq -p=toml -o=json '(.data.paseoDaemon = false | .data.orcaServer = false) | .data.orcaServer == false' \"${config}\""
    return 1
  fi
  if [ "$orca_value" != false ]; then
    log_warn "Integration opt-out migration aborted because updated data.orcaServer is not false; original config is unchanged"
    log_warn_cont "Check transformed flags (expect true): yq -p=toml -o=json '(.data.paseoDaemon = false | .data.orcaServer = false) | .data.orcaServer == false' \"${config}\""
    return 1
  fi

  mv "$temporary" "$config"
  trap - EXIT
  log_detail "Persisted paseoDaemon=false and orcaServer=false"
}

main "$@"
