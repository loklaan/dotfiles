#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Normalize TMPDIR (strip trailing slash for consistent path construction)
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly LOG_FILE="${TMPDIR}/$(basename "$0").${TIMESTAMP}.log"

# Redirect all output to both terminal and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Enable debug tracing if requested
if [ "${DEBUG:-0}" = "1" ]; then
  set -x
fi

#/ Usage:
#/   install.sh [OPTIONS]
#/
#/ Description:
#/   Installs dotfiles and packages.
#/
#/ Environment Variables:
#/   DEBUG:                   Set to 1 to enable command tracing (set -x) in logs.
#/   CONFIG_BWS_ACCESS_TOKEN: Optional. For authentication with Bitwarden Secrets.
#/                            When empty, templates using secrets output placeholders.
#/   CONFIG_SIGNING_KEY:      Optional. The primary key of the signing GPG keypair.
#/                            When empty, commit signing is disabled.
#/   CONFIG_GH_USER:          Dotfiles GitHub user. (default: loklaan)
#/   CONFIG_EMAIL:            Personal email for Git. (default: bunn@lochlan.io)
#/   CONFIG_EMAIL_WORK:       Work email for Git. (default: lochlan@canva.com)
#/
#/ Options:
#/   --skip-install-packages: Skip package installation (dotfiles only)
#/   --gui:                   Include GUI app packages (macOS only)
#/   --help:                  Display this help message
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

  supported_colors=$(tput colors 2>/dev/null || echo 0)
  if [ -n "$supported_colors" ] && [ "$supported_colors" -gt 8 ]; then
    printf "\\033[${color}m%s\\033[0m\\n" "$1"
  else
    printf "%s\n" "$1"
  fi
}
info() { _print cyan "[INFO] $@" >&2 ; }
warning() { _print yellow "[WARNING] $@" >&2 ; }
error() { _print red "[ERROR] $@" >&2 ; }
fatal() { _print red bold "[FATAL] $@" >&2 ; exit 1 ; }

cleanup() {
  _print white dim "Log: $LOG_FILE" >&2
}

parse_args() {
  # Initialize flags with defaults
  skip_packages=1  # 1 = false (install packages), 0 = true (skip)
  install_gui=1    # 1 = false (no GUI), 0 = true (include GUI)

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      --skip-install-packages)
        skip_packages=0
        shift
        ;;
      --gui)
        install_gui=0
        shift
        ;;
      *)
        usage
        fatal "Unknown argument: $1"
        ;;
    esac
  done

  # Set config variables with defaults (all optional)
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
  mise use --global -y chezmoi@2.67.0 'ubi:bitwarden/sdk[exe=bws,tag_regex=^bws]@bws-v1.0.0' >/dev/null 2>&1

  # Generate chezmoi config to bypass interactive prompts
  generate_chezmoi_config

  # Run chezmoi init (skip scripts - they run after packages are installed)
  info "▶ Installing templated dotfiles with 'chezmoi init'"
  BWS_ACCESS_TOKEN="$config_bw_access_token" chezmoi init "$config_github_user" \
    --apply \
    --force \
    --exclude=scripts \
    --branch main

  # Install packages unless skipped
  if [ "$skip_packages" -eq 1 ]; then
    run_package_installation
    info "▶ Dotfiles and packages installed."
    info "╍ Run 'install-my-packages --gui' to install GUI apps."
  else
    info "▶ Dotfiles installed. Package installation skipped."
    info "╍ Run 'install-my-packages' to install packages later."
    info "  or  'install-my-packages --gui'"
  fi

  # Pull latest changes and run lifecycle scripts (completions, fonts, etc.)
  info "▶ Pulling latest dotfiles and running lifecycle scripts"
  chezmoi git pull
  BWS_ACCESS_TOKEN="$config_bw_access_token" chezmoi apply --force

  info "▶ Installation complete."
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

generate_chezmoi_config() {
  local config_dir="${HOME}/.config/chezmoi"
  local config_file="${config_dir}/chezmoi.toml"

  # Preserve existing config if present
  if [ -f "$config_file" ]; then
    info "╍ Using existing chezmoi config at $config_file"
    return 0
  fi

  info "╍ Pre-generating chezmoi config to bypass prompts"
  mkdir -p "$config_dir"

  # Determine brewprefix based on architecture
  local brewprefix=""
  if [ "$(get_os_kind)" = "macos" ]; then
    if [ "$(uname -m)" = "arm64" ]; then
      brewprefix="/opt/homebrew"
    else
      brewprefix="/usr/local"
    fi
  fi

  cat > "$config_file" << EOF
[data]
  email = "$config_email"
  emailWork = "$config_email_work"
  signingKey = "$config_signing_key"
  brewprefix = "$brewprefix"
EOF
  info "╍ Wrote config to $config_file"
}

run_package_installation() {
  local install_script="${HOME}/.local/bin/install-my-packages"

  if [ ! -x "$install_script" ]; then
    fatal "Package installation script not found: $install_script"
  fi

  # Build arguments based on flags
  local args=()
  if [ "$install_gui" -eq 0 ]; then
    args+=("--gui")
  fi

  # Run the installation script (skip empty args)
  if [ ${#args[@]} -eq 0 ]; then
    "$install_script"
  else
    "$install_script" "${args[@]}"
  fi
}

trap cleanup EXIT
_print magenta dim "[$TIMESTAMP] Starting $(basename "$0")"
main "$@"
