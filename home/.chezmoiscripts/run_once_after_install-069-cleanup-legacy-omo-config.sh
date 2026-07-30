#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

source "${HOME}/.local/lib/bash-logging.sh"
setup_session_logging "$(basename "$0")"

#/ Usage:
#/   run_once_after_install-069-cleanup-legacy-omo-config.sh
#/
#/ Description:
#/   One-time cleanup after porting OMO config to the unified ~/.omo/omo.jsonc.
#/   Chezmoi now renders the [opencode] block of ~/.omo/omo.jsonc and no longer
#/   manages the legacy ~/.config/opencode/oh-my-openagent.json. Chezmoi leaves
#/   unmanaged files in place, so this removes the orphaned legacy file plus the
#/   backup directories OMO's own config-unification migration left in ~/.omo.
#/
#/   Runs once (run_once) after the config scripts at 065-068. The modify
#/   template already strips the stale _dotfiles* keys from the live omo.jsonc,
#/   so this script only deletes files chezmoi cannot.
#/
#/ Options:
#/   --help:      Display this help message
usage() { grep '^#/' "$0" | cut -c4-; }

main() {
  if [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  local legacy="${HOME}/.config/opencode/oh-my-openagent.json"
  if [ -f "$legacy" ]; then
    rm -f "$legacy" "${legacy}.migrations.json"
    info "╍ Removed legacy OMO config: ${legacy}"
  fi

  local backup
  for backup in "${HOME}/.omo/"migration-backup-*-opencode-config; do
    [ -e "$backup" ] || continue
    rm -rf "$backup"
    info "╍ Removed OMO migration backup: ${backup}"
  done
}

main "$@"
