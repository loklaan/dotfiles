#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

source "${HOME}/.local/lib/bash-logging.sh"
setup_session_logging "$(basename "$0")"

#/ Usage:
#/   run_after_install-071-opencode2.sh
#/
#/ Description:
#/   Installs and refreshes the OpenCode 2 beta CLI (`opencode2`) into a private
#/   npm prefix that only the ~/.local/bin/opencode2 wrapper reads.
#/
#/   OpenCode 2 is a SEPARATE binary from OpenCode 1 and is designed to run
#/   alongside it (https://opencode.ai/v2/docs/migrate-v1). It is published as
#/   @opencode-ai/cli on the `beta` dist-tag. mise cannot manage it: mise's npm
#/   backend resolves `latest` to the 1.18.x line (OpenCode 1's package) and its
#/   ls-remote does not list the 0.0.0-beta-* builds at all, so a mise [tools]
#/   entry would install the wrong package. We install it here instead, tracking
#/   the `beta` tag rather than pinning, because the beta ships near-daily.
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

readonly PACKAGE="@opencode-ai/cli"
readonly DIST_TAG="beta"
readonly PREFIX="${HOME}/.local/share/opencode2"
readonly PACKAGE_JSON="${PREFIX}/lib/node_modules/@opencode-ai/cli/package.json"

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
# over the stub at bin/opencode2.exe. Without it the wrapper execs a stub.
select_platform_binary() {
  local package_dir="${PREFIX}/lib/node_modules/@opencode-ai/cli"

  if [ ! -f "${package_dir}/postinstall.mjs" ]; then
    warning "opencode2: postinstall.mjs missing; platform binary not selected"
    return 0
  fi

  if (cd "$package_dir" && node ./postinstall.mjs >/dev/null 2>&1); then
    log_detail "Selected platform binary for $(uname -s)/$(uname -m)"
  else
    warning "opencode2: postinstall failed; binary may not run"
  fi
}

main() {
  parse_args "$@"

  if ! command -v npm >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
    return 0
  fi

  log_step "OpenCode 2 beta CLI"

  local available
  available=$(npm view "${PACKAGE}@${DIST_TAG}" version 2>/dev/null || true)

  if [ -z "$available" ]; then
    warning "opencode2: could not resolve ${PACKAGE}@${DIST_TAG} (offline?)"
    return 0
  fi

  local current
  current=$(installed_version)

  if [ "$current" = "$available" ]; then
    log_detail "Already current: ${available}"
    return 0
  fi

  if [ -n "$current" ]; then
    log_detail "Updating ${current} -> ${available}"
  else
    log_detail "Installing ${available}"
  fi

  mkdir -p "$PREFIX"

  if ! npm install --global --prefix "$PREFIX" --ignore-scripts \
    --no-audit --no-fund --loglevel=error "${PACKAGE}@${available}" >/dev/null 2>&1; then
    warning "opencode2: npm install failed; leaving previous install in place"
    return 0
  fi

  select_platform_binary

  log_detail "Wrapper: ~/.local/bin/opencode2 (config: ~/.config/opencode2)"
}

main "$@"
