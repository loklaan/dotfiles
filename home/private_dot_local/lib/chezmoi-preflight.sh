# shellcheck shell=bash
# chezmoi-preflight.sh — pre-apply checks for chezmoi
#
# Sourced by chezmoi hooks (apply.pre, update.pre). Runs these checks:
#
#   1. mise self-heal (non-fatal): re-renders the managed mise config and
#      reconciles installed tools, so backend/version drift (e.g. legacy
#      ubi:bitwarden/sdk vs current github:bitwarden/sdk) is corrected
#      before any template renders. Without this, `chezmoi update` after
#      a backend migration leaves stale tools on PATH. Skipped under
#      --dry-run/-n: chezmoi runs hooks even then, and this step writes.
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
#   4. Setup reminder (non-fatal): flags a missing BWS token or commit-signing
#      key, with a pointer to df-setup.
#
# df-setup is the single source of truth for "what state is this
# machine in and what should the user do next". This script is the hook
# that wires it into chezmoi apply.
#
# Messages use the shared bash-logging shapes and are mirrored into the live
# session log (via the marker) so preflight warnings are recorded, not just
# printed to the terminal.

# Shared logging shapes. The hook sources chezmoi-session.sh from the chezmoi
# source tree before this file, but bash-logging is not loaded; on a fresh
# bootstrap the installed copy may not exist yet, so keep plain fallbacks.
if [ -r "${HOME}/.local/lib/bash-logging.sh" ]; then
  # shellcheck source=./bash-logging.sh
  source "${HOME}/.local/lib/bash-logging.sh"
fi
if ! command -v log_warn >/dev/null 2>&1; then
  log_warn() { printf 'warning ╍ %s\n' "$*" >&2; }
  log_warn_cont() { printf 'warning   %s\n' "$*" >&2; }
  log_detail() { printf 'info ╍ %s\n' "$*" >&2; }
  log_cont() { printf 'info   %s\n' "$*" >&2; }
fi

# Emit one line through the shared shapes and append the same (colourless)
# line to the live session log, if one is open.
_pf_emit() { # $1 = warn|info, $2 = 1 if continuation else 0, $3 = message
  local level="$1" cont="$2" message="$3" marker log

  if [ "$level" = "warn" ]; then
    if [ "$cont" = "1" ]; then log_warn_cont "$message"; else log_warn "$message"; fi
  else
    if [ "$cont" = "1" ]; then log_cont "$message"; else log_detail "$message"; fi
  fi

  marker="${HOME}/.cache/dotfiles/chezmoi-session-current"
  [ -r "$marker" ] || return 0
  log=$(head -n 1 "$marker" 2>/dev/null || true)
  [ -n "$log" ] && [ -w "$log" ] || return 0

  if [ "$level" = "warn" ]; then
    if [ "$cont" = "1" ]; then printf 'warning   %s\n' "$message" >> "$log"
    else printf 'warning ╍ %s\n' "$message" >> "$log"; fi
  else
    if [ "$cont" = "1" ]; then printf 'info   %s\n' "$message" >> "$log"
    else printf 'info ╍ %s\n' "$message" >> "$log"; fi
  fi
}

chezmoi_preflight() {
  _chezmoi_preflight_path_sanity
  _chezmoi_preflight_sync_mise
  _chezmoi_preflight_prune_unmanaged
  _chezmoi_preflight_tools
  _chezmoi_preflight_bws_token
  _chezmoi_preflight_setup_reminder
}

# ABORT an apply whose PATH is too short to render templates correctly.
#
# Templates branch on `lookPath` (e.g. tmux's default-shell, every tool
# allowlist in a Deno shebang). A truncated PATH therefore does not fail — it
# silently renders DIFFERENT, wrong files and writes them to $HOME. That makes it
# the one preflight condition worth aborting on rather than warning about.
#
# The trap that motivates this: invoking deno (or any tool) through a mise shim
# re-injects mise's full tool PATH into the child, so a harness that sets
# PATH=/usr/bin:/bin still resolves chezmoi and git and can run a REAL apply with
# a degraded PATH.
#
# The check self-disables during bootstrap: it only fires once one of the
# expected dirs exists under $HOME, and install.sh exports both ~/.local/bin and
# the mise shims onto PATH before it applies. The signal is deliberately
# HOME-scoped — a system-wide dir like /opt/homebrew/bin exists regardless of
# which HOME is in play, so including it would misread a fresh HOME as
# provisioned.
#
# Escape hatch: CHEZMOI_ALLOW_DEGRADED_PATH=1 for a deliberate minimal-PATH run.
_chezmoi_preflight_path_sanity() {
  [ "${CHEZMOI_ALLOW_DEGRADED_PATH:-}" = "1" ] && return 0

  local expected=(
    "${HOME}/.local/share/mise/shims"
    "${HOME}/.local/bin"
  )

  local dir any_exists=0 any_on_path=0
  for dir in "${expected[@]}"; do
    [ -d "$dir" ] || continue
    any_exists=1
    case ":${PATH}:" in
      *":${dir}:"*) any_on_path=1 ;;
    esac
  done

  # Nothing provisioned yet: a fresh machine mid-bootstrap. Nothing to compare.
  [ "$any_exists" = "1" ] || return 0
  [ "$any_on_path" = "1" ] && return 0

  _pf_emit warn 0 "Refusing to apply with a degraded PATH"
  _pf_emit warn 1 "PATH=${PATH}"
  _pf_emit warn 1 "None of these provisioned dirs is on PATH:"
  for dir in "${expected[@]}"; do
    [ -d "$dir" ] && _pf_emit warn 1 "  ${dir}"
  done
  _pf_emit warn 1 "Templates resolve binaries with lookPath, so this apply would render and write WRONG files."
  _pf_emit warn 1 "Restore PATH, or set CHEZMOI_ALLOW_DEGRADED_PATH=1 if you truly mean it."
  exit 1
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
      _pf_emit warn 0 "Failed to remove stale file ${path}"
  done
}

# True when the running chezmoi was invoked with --dry-run/-n. chezmoi runs
# hooks even under --dry-run, and exports its argv (space-separated, starting
# with the chezmoi executable) as CHEZMOI_ARGS. Short flags may be clustered
# (`-nv`), so any single-dash cluster containing n counts. Parsing stops at
# `--`, after which everything is a target path.
_chezmoi_preflight_is_dry_run() {
  local arg
  local IFS=$' \t\n'
  # shellcheck disable=SC2086 # deliberate word split of CHEZMOI_ARGS
  for arg in ${CHEZMOI_ARGS:-}; do
    case "$arg" in
      --) return 1 ;;
      --dry-run) return 0 ;;
      --*) ;;
      # Letters only, so an attached value such as `-S/src/dir` never matches.
      -*n*) [[ "$arg" =~ ^-[A-Za-z]+$ ]] && return 0 ;;
    esac
  done
  return 1
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

  # Everything below writes to disk (the mise config, mise installs). A
  # dry-run must not mutate anything, so skip the whole block.
  if _chezmoi_preflight_is_dry_run; then
    _pf_emit info 0 "Skipping mise sync (dry run)"
    return 0
  fi

  # Copy the managed mise config, lock and lock sidecars to disk first, so
  # `mise install` below sees version/backend changes before any template
  # renders. A nested `chezmoi apply` cannot do this: the outer apply holds
  # chezmoi's persistent-state lock, so it always failed here. The files are
  # plain (not templates), so a copy from the source dir is the same output.
  local src="${CHEZMOI_SOURCE_DIR:-$(chezmoi source-path 2>/dev/null)}"
  local from="${src}/private_dot_config/mise" to="${HOME}/.config/mise"
  if [ ! -f "${from}/config.toml" ] || [ ! -f "${from}/mise.lock" ]; then
    _pf_emit warn 0 "Missing managed mise config in ${from}"
    return 0
  fi
  # The repo's own .mise.toml defines [hooks], which mise refuses to load from
  # an untrusted directory, so every mise call inside the checkout would fail.
  # chezmoi already runs this repo's code, so trusting it adds no exposure.
  [ -f "${src%/home}/.mise.toml" ] && mise trust --quiet "${src%/home}/.mise.toml" >/dev/null 2>&1
  mkdir -p "$to"
  local f
  for f in config.toml mise.lock; do
    cmp -s "${from}/${f}" "${to}/${f}" || cp "${from}/${f}" "${to}/${f}"
  done
  if [ -d "${from}/dot_mise" ]; then
    mkdir -p "${to}/.mise"
    cp -R "${from}/dot_mise/." "${to}/.mise/"
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
    _pf_emit warn 0 "mise install reported errors"
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

    _pf_emit warn 0 "Missing tools: ${list}"
    _pf_emit warn 1 "Some config will be incomplete — run install.sh to set up:"
    _pf_emit warn 1 "${HOME}/.local/share/chezmoi/install.sh"
  fi
}

# Probe BWS token validity via `df-setup --probe-bws`. Exit codes:
#   0 = token valid
#   1 = token missing (not configured on this machine — benign)
#   2 = token present but rejected by BWS server (expired / revoked)
#
# Templates read secrets via bws-get-or-empty (handed the token-file PATH, not
# the token value, so the secret never reaches any process argv), which
# soft-fails to empty on any error — so an invalid token produces empty secrets
# rather than crashing apply. That silent degradation is worse than a visible
# warning, so surface
# state 2 here with a pointer to df-setup. We do NOT abort: apply with empty
# secrets is a valid state (e.g. fresh machine, or user intentionally
# operating without the secret store).
_CHEZMOI_PREFLIGHT_BWS_MISSING=0
_chezmoi_preflight_bws_token() {
  local setup_bin="${HOME}/.local/bin/df-setup"

  if [ ! -x "$setup_bin" ]; then
    return 0
  fi

  local rc=0
  "$setup_bin" --probe-bws >/dev/null 2>&1 || rc=$?

  case "$rc" in
    0)
      return 0
      ;;
    1)
      _CHEZMOI_PREFLIGHT_BWS_MISSING=1
      return 0
      ;;
    2)
      _pf_emit warn 0 "BWS token is present but rejected by the server"
      _pf_emit warn 1 "Secrets will be empty for this apply — run 'df-setup' for guidance"
      return 0
      ;;
    *)
      _pf_emit warn 0 "df-setup --probe-bws returned unexpected exit ${rc}"
      return 0
      ;;
  esac
}

# Remind about incomplete setup: no BWS token (from the probe above) or no
# commit-signing key. The key lives in chezmoi data, which a hook cannot read,
# so .chezmoi.toml.tmpl exports DF_SIGNING_KEY_SET via [scriptEnv]; an
# unset value (config predating it) is treated as "set" to avoid a false alarm.
_chezmoi_preflight_setup_reminder() {
  local no_signing=0
  [ "${DF_SIGNING_KEY_SET:-1}" = "0" ] && no_signing=1
  [ "$_CHEZMOI_PREFLIGHT_BWS_MISSING" = "1" ] || [ "$no_signing" = "1" ] || return 0

  [ "$_CHEZMOI_PREFLIGHT_BWS_MISSING" = "1" ] &&
    _pf_emit warn 0 "Missing BWS token (npm auth, GitHub tokens)"
  [ "$no_signing" = "1" ] &&
    _pf_emit warn 0 "Missing signing key (git commit signing)"
  _pf_emit warn 1 "Run 'df-setup' for instructions"
}

chezmoi_preflight
