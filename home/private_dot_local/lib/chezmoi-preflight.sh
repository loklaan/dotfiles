# shellcheck shell=bash
# chezmoi-preflight.sh — pre-apply checks for chezmoi
#
# Sourced by chezmoi hooks (apply.pre, update.pre). Runs two checks:
#
#   1. Missing binaries (non-fatal): warns if tools that templates depend on
#      aren't installed. Templates are written to degrade gracefully.
#
#   2. BWS token health (non-fatal): probes the token via dotfiles-setup
#      --probe-bws. Templates fetch secrets through bws-get-or-empty, which
#      already falls through to empty on any failure, so a bad token won't
#      crash apply. The preflight still surfaces a warning + a pointer to
#      dotfiles-setup so silent degradation is visible to the user.
#
# dotfiles-setup is the single source of truth for "what state is this
# machine in and what should the user do next". This script is the hook
# that wires it into chezmoi apply.

chezmoi_preflight() {
  _chezmoi_preflight_tools
  _chezmoi_preflight_bws_token
}

_chezmoi_preflight_tools() {
  local missing=()

  command -v bws >/dev/null 2>&1 || missing+=("bws")
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  command -v node >/dev/null 2>&1 || missing+=("node")

  if [ "${#missing[@]}" -gt 0 ]; then
    local list
    list=$(printf '%s, ' "${missing[@]}")
    list="${list%, }"

    printf '\033[33m⚠ Missing tools: %s\033[0m\n' "$list" >&2
    printf '\033[2;37m  Some config will be incomplete. Run install.sh to set up:\033[0m\n' >&2
    printf '\033[2;37m  %s/.local/share/chezmoi/install.sh\033[0m\n' "$HOME" >&2
  fi
}

# Probe BWS token validity via `dotfiles-setup --probe-bws`. Exit codes:
#   0 = token valid
#   1 = token missing (not configured on this machine — benign)
#   2 = token present but rejected by BWS server (expired / revoked)
#
# Templates now read secrets via bws-get-or-empty, which soft-fails to
# empty on any error — so an invalid token no longer crashes apply, it
# just silently produces empty secrets. That silent degradation is worse
# than a visible warning, so surface state 2 here with a pointer to
# dotfiles-setup. We do NOT abort: apply with empty secrets is a valid
# state (e.g. fresh machine, or user intentionally operating without
# the secret store).
_chezmoi_preflight_bws_token() {
  local setup_bin="${HOME}/.local/bin/dotfiles-setup"

  if [ ! -x "$setup_bin" ]; then
    return 0
  fi

  local rc=0
  "$setup_bin" --probe-bws >/dev/null 2>&1 || rc=$?

  case "$rc" in
    0|1)
      return 0
      ;;
    2)
      printf '\033[33m⚠ BWS token is present but rejected by the server\033[0m\n' >&2
      printf '\033[2;37m  Secrets will be empty for this apply. For guidance:\033[0m\n' >&2
      printf '\033[2;37m  %s/.local/bin/dotfiles-setup\033[0m\n' "$HOME" >&2
      return 0
      ;;
    *)
      printf '\033[33m⚠ dotfiles-setup --probe-bws returned unexpected exit %d\033[0m\n' "$rc" >&2
      return 0
      ;;
  esac
}

chezmoi_preflight
