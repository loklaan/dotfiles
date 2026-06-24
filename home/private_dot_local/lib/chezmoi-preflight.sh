# shellcheck shell=bash
# chezmoi-preflight.sh — pre-apply checks for chezmoi
#
# Sourced by chezmoi hooks (apply.pre, update.pre). Runs three checks:
#
#   1. mise self-heal (non-fatal): re-renders the managed mise config and
#      reconciles installed tools, so backend/version drift (e.g. legacy
#      ubi:bitwarden/sdk vs current github:bitwarden/sdk) is corrected
#      before any template renders. Without this, `chezmoi update` after
#      a backend migration leaves stale tools on PATH.
#
#   2. Missing binaries (non-fatal): warns if tools that templates depend
#      on aren't installed. Templates are written to degrade gracefully.
#
#   3. BWS token health (non-fatal): probes the token via df-setup
#      --probe-bws. Templates fetch secrets through bws-get-or-empty, which
#      already falls through to empty on any failure, so a bad token won't
#      crash apply. The preflight still surfaces a warning + a pointer to
#      df-setup so silent degradation is visible to the user.
#
# df-setup is the single source of truth for "what state is this
# machine in and what should the user do next". This script is the hook
# that wires it into chezmoi apply.

chezmoi_preflight() {
  _chezmoi_preflight_sync_mise
  _chezmoi_preflight_prune_unmanaged
  _chezmoi_preflight_tools
  _chezmoi_preflight_bws_token
}

# Remove files that were once managed but have since been deleted from the
# repo. Chezmoi's `apply` does not retroactively remove files that were
# unmanaged after they hit disk; without this, a stale file lingers
# indefinitely and can poison tools that scan its containing directory.
#
# Each entry is a path under $HOME that we know is unsafe to leave behind.
# Keep the list narrow: deletes are destructive, and a too-broad rule could
# clobber a user's hand-rolled file. Pair every entry with the commit that
# removed it from the repo so future-us can prune this list when it grows.
_chezmoi_preflight_prune_unmanaged() {
  local stale=(
    # 77ee265 — drop yolo agent config for opencode. Stale frontmatter
    # `permission: allow` (string) is rejected by opencode 1.15's agent
    # schema, which crashes startup with ConfigInvalidError.
    ".config/opencode/agents/yolo.md"
  )

  local rel
  for rel in "${stale[@]}"; do
    local path="${HOME}/${rel}"
    [ -e "$path" ] || continue
    rm -f "$path" 2>/dev/null || \
      printf '\033[33m⚠ preflight: failed to remove stale file %s\033[0m\n' "$path" >&2
  done
}

# Re-render the managed mise config and reconcile installed tools. Runs
# first so subsequent checks (and templates) see the correct binaries on
# PATH after a backend migration or version bump.
_chezmoi_preflight_sync_mise() {
  # Prevent infinite recursion: the nested `chezmoi apply` below would
  # re-trigger this hook. Guard with an env var.
  [ "${CHEZMOI_PREFLIGHT_RUNNING:-}" = "1" ] && return 0
  export CHEZMOI_PREFLIGHT_RUNNING=1

  command -v chezmoi >/dev/null 2>&1 || return 0
  command -v mise >/dev/null 2>&1 || return 0

  local mise_config="${HOME}/.config/mise/config.toml"

  # Render the managed mise config to disk first, so `mise install` below
  # picks up version/backend migrations before any template renders.
  if ! chezmoi apply --force "$mise_config" >/dev/null 2>&1; then
    printf '\033[33m⚠ preflight: failed to apply managed mise config\033[0m\n' >&2
    return 0
  fi

  # Remove the deprecated ubi:bitwarden/sdk install if a machine was
  # bootstrapped before the github: migration. The managed config only
  # references github:bitwarden/sdk, so the ubi: install is always dead
  # weight once this hook has run.
  if mise ls 2>/dev/null | grep -q '^ubi:bitwarden/sdk'; then
    mise uninstall -a 'ubi:bitwarden/sdk' >/dev/null 2>&1 || true
  fi

  # Prune stale github:bitwarden/sdk versions — keep only the pinned one.
  # After a `version =` bump, the prior install lingers; nothing
  # references it. mise current reports the version the config selects.
  local bws_pin ver
  bws_pin=$(mise current 'github:bitwarden/sdk' 2>/dev/null | tr -d '[:space:]')
  if [ -n "$bws_pin" ]; then
    while read -r ver; do
      if [ -n "$ver" ] && [ "$ver" != "$bws_pin" ]; then
        mise uninstall "github:bitwarden/sdk@${ver}" >/dev/null 2>&1 || true
      fi
    done < <(mise ls 2>/dev/null | awk '$1 == "github:bitwarden/sdk" {print $2}')
  fi

  # Reconcile installed tools with the (now-fresh) config.
  mise install -y >/dev/null 2>&1 || \
    printf '\033[33m⚠ preflight: mise install reported errors\033[0m\n' >&2
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

# Probe BWS token validity via `df-setup --probe-bws`. Exit codes:
#   0 = token valid
#   1 = token missing (not configured on this machine — benign)
#   2 = token present but rejected by BWS server (expired / revoked)
#
# Templates read secrets via bws-get-or-empty, which soft-fails to empty on
# any error — so an invalid token produces empty secrets rather than crashing
# apply. That silent degradation is worse than a visible warning, so surface
# state 2 here with a pointer to df-setup. We do NOT abort: apply with empty
# secrets is a valid state (e.g. fresh machine, or user intentionally
# operating without the secret store).
_chezmoi_preflight_bws_token() {
  local setup_bin="${HOME}/.local/bin/df-setup"

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
      printf '\033[2;37m  %s/.local/bin/df-setup\033[0m\n' "$HOME" >&2
      return 0
      ;;
    *)
      printf '\033[33m⚠ df-setup --probe-bws returned unexpected exit %d\033[0m\n' "$rc" >&2
      return 0
      ;;
  esac
}

chezmoi_preflight
