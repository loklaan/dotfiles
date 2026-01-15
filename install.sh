#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Source shared logging library (from chezmoi source dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/home/private_dot_local/lib/bash-logging.sh"
setup_session_logging "$(basename "$0")"

#/ Usage:
#/   install.sh [OPTIONS]
#/
#/ Description:
#/   Installs dotfiles and packages.
#/
#/ Environment Variables:
#/   DEBUG:                     Set to 1 to enable command tracing (set -x) in logs.
#/   CONFIG_BWS_ACCESS_TOKEN:   Optional. Bitwarden Secrets access token (used to fetch age identity).
#/                              When empty, prompts interactively (or skips if non-TTY).
#/   CONFIG_AGE_IDENTITY_TYPE:  Optional. Override auto-detected age identity type.
#/                              Values: personal, work-machine, work-remote.
#/                              Auto-detection: work-remote (Canva devbox), work-machine (MDM enrolled),
#/                              otherwise personal.
#/   CONFIG_SIGNING_KEY:        Optional. The primary key of the signing GPG keypair.
#/                              When empty, commit signing is disabled.
#/   CONFIG_GH_USER:            Dotfiles GitHub user. (default: loklaan)
#/   CONFIG_EMAIL:              Personal email for Git. (default: bunn@lochlan.io)
#/   CONFIG_EMAIL_WORK:         Work email for Git. (default: lochlan@canva.com)
#/
#/ Options:
#/   --help:                    Display this help message
usage() { grep '^#/' "$0" | cut -c4-; }

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

main() {
  parse_args "$@"
  info "▶ Starting installation of dotfiles!"

  # Install required shell & locale packages for OS
  if command -v git >/dev/null 2>&1 && command -v zsh >/dev/null 2>&1; then
    info "╍ Found 'git' and 'zsh' already installed"
  else
    info "▶ Installing critical packages (shell, locale)"
    os_kind=$(get_os_kind)
    case $os_kind in
      windows|android) fatal "Nope, $os_kind is not supported." ;;
      macos)
        info "╍ Running 'brew install git zsh'"
        if ! command -v brew >/dev/null 2>&1; then
          fatal "Homebrew is not installed. Please install Homebrew first: https://brew.sh"
        fi
        brew install git zsh
        ;;
      linux)
        if [ "$(id -u)" = "0" ]; then
          Sudo=''
          info "╍ Root user detected, skipping sudo for following commands"
        elif which sudo >/dev/null 2>&1; then
          Sudo='sudo'
          info "╍ Sudo detected, using it for following commands"
        else
          Sudo=''
          warning "╍ Cannot find 'sudo' so will attempt to run following commands without it"
        fi

        linux_distro=$(get_linux_distro)
        case $linux_distro in
          alpine)
            info "╍ Running 'apk add git zsh'"
            $Sudo apk add --update --no-cache git zsh
          ;;
          amzn|rhel|fedora|rocky)
            info "╍ Running 'yum install git zsh'"
            $Sudo yum update -y
            $Sudo yum install -y git zsh
          ;;
          ubuntu|debian)
            info "╍ Running 'apt install git zsh locales'"
            $Sudo apt update
            $Sudo apt --no-install-recommends -y install git zsh locales

            info "╍ Running 'locale-gen en_US.UTF-8'"
            $Sudo locale-gen en_US.UTF-8
          ;;
          *)
            fatal "The \"$linux_distro\" is not supported yet. Add '$linux_distro' and it's package manager to \`install.sh\`."
          ;;
        esac
        ;;
    esac
  fi

  # Install mise & critical packages
  if ! command -v mise >/dev/null 2>&1; then
    info "▶ Installing critical packages (mise , chezmoi, bitwarden)"
    info "╍ Running 'gpg --recv-keys' for install script verification"
    gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 0x7413A06D >/dev/null 2>&1
    tmp_mise_install_sh=$(mktemp)
    info "╍ Running 'curl mise.jdx.dev' for install script"
    curl https://mise.jdx.dev/install.sh.sig 2>/dev/null | gpg --decrypt 2>/dev/null > "$tmp_mise_install_sh"
    info "╍ Running downloaded install script"
    sh "$tmp_mise_install_sh" 2>/dev/null
  fi
  export PATH="${HOME}/.local/bin:${PATH}"
  export PATH="$HOME/.local/share/mise/shims:$PATH"
  info "╍ Running mise for chezmoi and bitwarden"
  mise use --global -y chezmoi@2.67.0 'ubi:bitwarden/sdk[exe=bws,tag_regex=^bws]@bws-v1.0.0' >/dev/null 2>&1

  # Run chezmoi init (skip scripts - they run after packages are installed)
  #  - Prompts should be kept in-sync with .chezmoi.toml.tmpl config
  info "▶ Installing templated dotfiles with 'chezmoi init'"
  config_github_user="${CONFIG_GH_USER:-"loklaan"}"
  config_email="${CONFIG_EMAIL:-$(result=$(chezmoi execute-template "{{ .email }}" 2>/dev/null || echo ""); echo "${result:-"bunn@lochlan.io"}")}"
  config_email_work="${CONFIG_EMAIL_WORK:-$(result=$(chezmoi execute-template "{{ .emailWork }}" 2>/dev/null || echo ""); echo "${result:-"lochlan@canva.com"}")}"
  config_signing_key="${CONFIG_SIGNING_KEY:-$(result=$(chezmoi execute-template "{{ .signingKey }}" 2>/dev/null || echo ""); echo "${result:-}")}"

  # Age identity setup - fetch from BWS if token provided or identity not present
  age_identity_path="${HOME}/.config/chezmoi/secrets/age-key.txt"
  config_bws_token="${CONFIG_BWS_ACCESS_TOKEN:-}"

  if [ -n "$config_bws_token" ]; then
    # Explicit token provided - always fetch (allows refresh/rotation)
    info "╍ BWS token provided, fetching age identity"
  elif [ -f "$age_identity_path" ]; then
    # Existing identity found, no token provided - skip fetch
    info "╍ Found existing age identity"
    config_bws_token=""
  elif [ -t 0 ]; then
    # No identity, no token, interactive - prompt
    read -rsp "BWS access token (to fetch age identity, or Enter to skip): " config_bws_token
    echo
  fi

  if [ -n "$config_bws_token" ]; then
    # Auto-detect identity type based on environment
    if [[ "${CODER_AGENT_URL:-}" == *canva* ]] || [[ "${DEVBOX_EMAIL:-}" == *@canva.com ]]; then
      detected_identity_type="work-remote"
    elif profiles status -type enrollment 2>/dev/null | grep -q "MDM enrollment: Yes"; then
      detected_identity_type="work-machine"
    else
      detected_identity_type="personal"
    fi
    identity_type="${CONFIG_AGE_IDENTITY_TYPE:-$detected_identity_type}"
    if [ -n "${CONFIG_AGE_IDENTITY_TYPE:-}" ]; then
      info "╍ Using identity type: $identity_type (override, detected: $detected_identity_type)"
    else
      info "╍ Using identity type: $identity_type (auto-detected)"
    fi

    # Read BWS secret ID from template file (format: identity_type=uuid)
    identity_uuids_file="${SCRIPT_DIR}/home/.chezmoitemplates/age-identity-uuids-tmpl"
    if [ ! -f "$identity_uuids_file" ]; then
      fatal "Missing identity UUIDs file: $identity_uuids_file"
    fi

    bws_secret_id=$(grep "^${identity_type}=" "$identity_uuids_file" | cut -d= -f2)
    if [ -z "$bws_secret_id" ]; then
      fatal "Unknown identity type: $identity_type. Valid types: $(cut -d= -f1 "$identity_uuids_file" | tr '\n' ', ' | sed 's/,$//')"
    fi

    info "╍ Fetching age identity ($identity_type) from BWS"
    mkdir -p "$(dirname "$age_identity_path")"
    bws secret get "$bws_secret_id" --access-token "$config_bws_token" | jq -r '.value' > "$age_identity_path"
    chmod 600 "$age_identity_path"
    info "╍ Saved age identity to $age_identity_path"
  else
    warning "╍ No age identity found - secrets requiring decryption will not be available"
    info "╍ To set up: provide CONFIG_BWS_ACCESS_TOKEN or manually create $age_identity_path"
  fi

  chezmoi init "$config_github_user" \
    --data=false \
    --promptString="Email for you=${config_email},Email for Canva=${config_email_work},Your commit-signing key (e.g. public ssh/gpg key)=${config_signing_key}" \
    --apply \
    --force \
    --exclude=scripts \
    --branch main

  # Pull latest changes and run lifecycle scripts (packages, completions, fonts, etc.)
  info "▶ Pulling latest dotfiles and running lifecycle scripts"
  chezmoi git pull
  chezmoi apply --force

  info "▶ Installation complete."
  info "╍ Run 'install-my-packages --gui' to install GUI apps."
}

get_os_kind() {
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "${os}" in
    cygwin_nt*) goos="windows" ;;
    linux)
      if command -v termux-info >/dev/null 2>&1; then
        goos="android"
      else
        goos="linux"
      fi
      ;;
    mingw*) goos="windows" ;;
    msys_nt*) goos="windows" ;;
    darwin*) goos="macos" ;;
    *) goos="${os}" ;;
  esac
  printf '%s' "${goos}"
}

get_linux_distro() {
  (
    . /etc/os-release
    echo "$ID"
  )
}

trap print_log_path EXIT
main "$@"
