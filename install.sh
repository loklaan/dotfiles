#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Normalize TMPDIR (strip trailing slash for consistent path construction)
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly LOG_FILE="${TMPDIR}/$(basename "$0").${TIMESTAMP}.log"

#/ Usage:
#/   install.sh
#/
#/ Description:
#/   Installs dotfiles and packages.
#/
#/ Environment Variables:
#/   CONFIG_BWS_ACCESS_TOKEN: Required. For authentication—with Bitwarden Secrets.
#/   CONFIG_SIGNING_KEY:      Required. The primary key of the signing GPG keypair; use `gpg -K` to find it.
#/   CONFIG_GH_USER:          Dotfiles GitHub user.
#/   CONFIG_EMAIL:            Personal email address for Git configuration.
#/   CONFIG_EMAIL_WORK:       Work email address for Git configuration.
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
  if [ -z "${CONFIG_BWS_ACCESS_TOKEN:-}" ] || [ -z "${CONFIG_SIGNING_KEY:-}" ]; then
    usage
    echo "" >&2
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

  config_bw_access_token="${CONFIG_BWS_ACCESS_TOKEN:-}"
  config_signing_key="${CONFIG_SIGNING_KEY:-}"
  config_github_user="${CONFIG_GH_USER:-"loklaan"}"
  config_email="${CONFIG_EMAIL:-"bunn@lochlan.io"}"
  config_email_work="${CONFIG_EMAIL_WORK:-"lochlan@canva.com"}"
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
  _print white dim "Tip: Install non-critical packages anytime with \`install-my-packages\`"
  mise use --global chezmoi@2.67.0 'ubi:bitwarden/sdk[tag_regex=^bws,exe=bws]@bws-v1.0.0'

  # Run chezmoi init
  info "▶ Installing templated dotfiles with 'chezmoi init'"
  BWS_ACCESS_TOKEN="$config_bw_access_token" exec chezmoi init "$config_github_user" \
    --apply \
    --branch main \
    --promptString email="$config_email" \
    --promptString emailWork="$config_email_work" \
    --promptString signingKey="$config_signing_key"

  info "▶ Installed dotfiles. Done."
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

trap cleanup EXIT
_print magenta dim "[$TIMESTAMP] Starting $(basename "$0")"
main "$@"
