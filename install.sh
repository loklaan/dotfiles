#!/bin/sh

require_commands() {
  for cmd in "$@"
  do
    if ! command -v $cmd >/dev/null 2>&1; then
      echo "Error: Command $cmd required but not found. Ensure all of the following commands are install - $@"
      exit 1
    fi
  done
}

case "$(uname)" in
  Darwin)
    require_commands ${("curl" "bash")[@]}
    case "$(uname -m)" in
      arm64) readonly PREFIX=/opt/homebrew ;;
      x86_64) readonly PREFIX=/usr/local ;;
    esac
    PATH=/usr/sbin:/usr/bin:/sbin:/bin
    if [ ! -e "${PREFIX:?}/bin/brew" ]; then
      install="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      bash -c "${install}"
    fi
    PATH="${PREFIX:?}/bin:${PATH}"
    pkgs=""
    if ! command -v chezmoi >/dev/null 2>&1; then
      pkgs=chezmoi
    fi
    if ! command -v bw >/dev/null 2>&1; then
      pkgs+=bitwarden-cli
    fi
    pkgs_str=${pkgs[@]}
    if [ -n "$pkgs_str" ]; then
      brew install $pkgs_str
    fi
    ;;
esac

export BW_SESSION=$(bw login "${BITWARDEN_EMAIL:-'bunn@lochlan.io'}" --raw)
chezmoi init https://github.com/${GITHUB_USERNAME:-loklaan}/dotfiles.git --apply --keep-going
