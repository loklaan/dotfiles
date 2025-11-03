#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly LOG_FILE="/tmp/$(basename "$0").${TIMESTAMP}.log"

#/ Usage:
#/   install.sh
#/
#/ Description:
#/   Installs dotfiles and packages.
#/
#/ Environment Variables:
#/   CONFIG_BWS_ACCESS_TOKEN: For authentication—with Bitwarden Secrets.
#/   CONFIG_GH_USER:          Dotfiles GitHub user.
#/
#/ Options:
#/   --help:      Display this help message
usage() { grep '^#/' "$0" | cut -c4-; }
_print() {
  case "$1" in
    black) color="30" ;;
    red) color="31" ;;
    green) color="32" ;;
    yellow) color="33" ;;
    blue) color="34" ;;
    magenta) color="35" ;;
    cyan) color="36" ;;
    white) color="37" ;;
    *) echo "Unknown color: $1" >&2; return 1 ;;
  esac

  shift
  while [ "$#" -gt 1 ]; do
    case "$1" in
      bold) color="${color};1" ;;
      italic) color="${color};3" ;;
      underline) color="${color};4" ;;
      dim) color="${color};2" ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
    shift
  done

  supported_colors=$(tput colors 2>/dev/null)
  if [ "$supported_colors" -gt 8 ]; then
    printf "\\033[${color}m%s\\033[0m\\n" "$1"
  else
    printf "%s\n" "$1"
  fi
}
info() { _print cyan "[INFO] $@" | tee -a "$LOG_FILE" >&2 ; }
warning() { _print yellow "[WARNING] $@" | tee -a "$LOG_FILE" >&2 ; }
error() { _print red "[ERROR] $@" | tee -a "$LOG_FILE" >&2 ; }
fatal() { _print red bold "[FATAL] $@" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }


cleanup() {
  echo "" >&2
  _print white dim "Log: $LOG_FILE" >&2
}

parse_args() {
  if [ -z "${CONFIG_BWS_ACCESS_TOKEN-}" ] ]; then
    usage
    fatal "Missing required environment variables."
  fi

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

  config_bw_access_token="${CONFIG_BWS_ACCESS_TOKEN}"
  config_github_user="${CONFIG_GH_USER:-"loklaan"}"
  config_email="${CONFIG_EMAIL:-"bunn@lochlan.io"}"
  config_email_work="${CONFIG_EMAIL_WORK:-"lochlan@canva.com"}"
  config_signing_key="${CONFIG_SIGNING_KEY:-"~/.ssh/id_rsa.pub"}"
}

main() {
  parse_args "$@"
  info "Installing ...dotfiles!"

  # Install required shell & locale packages for OS
  if command -v git >/dev/null 2>&1 && command -v zsh >/dev/null 2>&1; then
    info "▶ Found 'git' and 'zsh' already installed"
  else
    info "▶ Installing shell & locale"
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
          *)
            info "╍ Running 'apt-get install git zsh locales'"
            $Sudo apt-get update
            $Sudo apt-get -y install git zsh locales
            #if [ "$VERSION" != "14.04" ]; then
            #  $Sudo apt-get -y install locales-all
            #fi
            info "╍ Running 'locale-gen en_US.UTF-8'"
            $Sudo locale-gen en_US.UTF-8
        esac
        ;;
    esac
  fi

  # Install mise & required packages
  if ! command -v mise >/dev/null 2>&1; then
    info "▶ Installing mise"
    info "╍ Running 'gpg --recv-keys' for mise install script verification"
    gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 0x7413A06D > /dev/null 2>&1
    tmp_mise_install_sh=$(mktemp)
    info "╍ Running 'curl mise.jdx.dev' for install script"
    curl https://mise.jdx.dev/install.sh.sig | gpg --decrypt > "$tmp_mise_install_sh"
    info "╍ Running mise install script"
    sh "$tmp_mise_install_sh"
  fi
  export PATH="${HOME}/.local/bin:${PATH}"
  export PATH="$HOME/.local/share/mise/shims:$PATH"
  info "▶ Installing required packages with mise"
  mise use --global chezmoi 'ubi:bitwarden/sdk[tag_regex=^bws,exe=bws]@bws-v1.0.0'

  # Run chezmoi init
  info "▶ Running 'chezmoi init'"
  BWS_ACCESS_TOKEN="$config_bw_access_token" exec chezmoi init "$config_github_user" \
    --apply \
    --branch to-mise-dependency-management \
    --promptString email="$config_email" \
    --promptString emailWork="$config_email_work" \
    --promptString signingKey="$config_signing_key"
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

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  trap cleanup EXIT
  main "$@"
fi
