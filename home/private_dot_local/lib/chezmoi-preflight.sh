# chezmoi-preflight.sh — pre-apply checks for required tools
#
# Sourced by chezmoi hooks (apply.pre, update.pre). Prints warnings
# for missing binaries that templates depend on, then continues.
# Does not block apply — templates degrade gracefully, but the user
# should know their setup is incomplete.

chezmoi_preflight() {
  local missing=()

  command -v bws >/dev/null 2>&1 || missing+=("bws")
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

chezmoi_preflight
