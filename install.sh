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
#/   CONFIG_BWS_ACCESS_TOKEN:   Optional. Bitwarden Secrets access token.
#/                              When empty, prompts interactively (or skips if non-TTY).
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

  # BWS token setup - save to file if provided
  bws_token_path="${HOME}/.config/chezmoi/secrets/bws-access-token.txt"
  config_bws_token="${CONFIG_BWS_ACCESS_TOKEN:-}"

  if [ -n "$config_bws_token" ]; then
    info "╍ BWS token provided, saving to $bws_token_path"
    mkdir -p "$(dirname "$bws_token_path")"
    printf '%s' "$config_bws_token" > "$bws_token_path"
    chmod 600 "$bws_token_path"
  elif [ -f "$bws_token_path" ]; then
    info "╍ Found existing BWS token"
  elif [ -t 0 ]; then
    read -rsp "BWS access token (or Enter to skip): " config_bws_token
    echo
    if [ -n "$config_bws_token" ]; then
      mkdir -p "$(dirname "$bws_token_path")"
      printf '%s' "$config_bws_token" > "$bws_token_path"
      chmod 600 "$bws_token_path"
    fi
  else
    warning "╍ No BWS token found - secrets will not be available"
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
