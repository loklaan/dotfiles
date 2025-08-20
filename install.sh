#!/bin/sh
set -eu

echo "" >&2

#/ Usage:
#/   BITWARDEN_EMAIL=.. GITHUB_USERNAME=.. install.sh
#/
#/ Description:
#/   Installs dotfiles and dependencies.
#/
#/ Options:
#/   --help: Display this help message
usage() { grep '^#/' "$0" | cut -c4-; }
expr "$*" : ".*--help" > /dev/null && usage

bw_email="${BITWARDEN_EMAIL:-""}"
github_user="${GITHUB_USERNAME:-""}"
if [ "$bw_email" = "" ] || [ "$github_user" = "" ]; then
  usage
  exit 1;
fi

main() {
  print_colored magenta bold "Installing dotfiles!" >&2
  echo "" >&2

  bin_dir="${HOME}/.local/bin"

  # Install dependencies
  mkdir -p "$bin_dir"
  if ! chezmoi="$(command -v chezmoi)"; then
    chezmoi_install_url="get.chezmoi.io"
    print_colored cyan italic " ▷ Installing chezmoi " >&2
    chezmoi="${bin_dir}/chezmoi"
    chezmoi_install_script="$(http_get $chezmoi_install_url)" || return 1
    sh -c "${chezmoi_install_script}" -- -b "${bin_dir}" || return 1
  fi
  if ! bitwarden="$(command -v bw)"; then
    bitwarden_install_url="https://vault.bitwarden.com/download/?app=cli&platform=$(get_bitwarden_os)"
    print_colored cyan italic " ▷ Installing bitwarden-cli " >&2
    bitwarden_zip="${bin_dir}/bw.zip"
    bitwarden="${bin_dir}/bw"
    http_download "${bitwarden_zip}" "$bitwarden_install_url" || return 1
    last_dir=$(pwd)
    cd "$(dirname "$bitwarden_zip")"
    unarchive "$bitwarden_zip" && rm "$bitwarden_zip" || return 1
    chmod +x "$bitwarden"
    cd "$last_dir"
  fi

  # Authenticate with credentials provider (used in chezmoi templates)
  print_colored cyan italic " ▶ Running 'bw login $bw_email --raw' " >&2
  counter=0
  bw_token=""
  while [ $counter -lt 3 ]; do
    set +e
    if ! bw_token="$("$bitwarden" login "$bw_email" --raw < /dev/tty)"; then
      if ! bw_token="$("$bitwarden" unlock --raw < /dev/tty)"; then
        counter=$((counter+1))
      else
        break
      fi
    else
      break
    fi
    set -e
  done
  if [ "$bw_token" = "" ]; then
    print_colored red bold "Error: Failed to login" >&2
    exit 1
  fi

  # Run chezmoi init
  print_colored cyan italic " ▶ Running '$chezmoi init $github_user --apply --keep-going' " >&2
  BW_SESSION="$bw_token" exec "$chezmoi" init "$github_user" --apply --keep-going
}

http_get() {
	source_url="${1:?"Source URL required"}"
	header="${2:-""}"
	tmpfile="$(mktemp)"
	http_download "${tmpfile}" "${source_url}" "${header}" || return 1
	body="$(cat "${tmpfile}")"
	rm -f "${tmpfile}"
	printf '%s\n' "${body}"
}

http_download_curl() {
	local_file="${1:?"Local file required"}"
	source_url="${2:?"Source URL required"}"
	header="${3:-""}"
	if [ -z "${header}" ]; then
		code="$(curl -w '%{http_code}' -sL -o "${local_file}" "${source_url}")"
	else
		code="$(curl -w '%{http_code}' -sL -H "${header}" -o "${local_file}" "${source_url}")"
	fi
	if [ "${code}" != "200" ]; then
	  print_colored "Error: Could not download $source_url (HTTP status: ${code})" >&2
		return 1
	fi
	return 0
}

http_download_wget() {
	local_file="${1:?"Local file required"}"
	source_url="${2:?"Source URL required"}"
	header="${3:-""}"
	if [ -z "${header}" ]; then
		wget -q -O "${local_file}" "${source_url}" || return 1
	else
		wget -q --header "${header}" -O "${local_file}" "${source_url}" || return 1
	fi
}

http_download() {
	if command -v curl >/dev/null 2>&1; then
		http_download_curl "${@}" || return 1
		return
	elif command -v wget >/dev/null 2>&1; then
		http_download_wget "${@}" || return 1
		return
	fi
	return 1
}

required_commands() {
  for cmd in "$@"
  do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      print_colored red bold "Error: Command $cmd required but not found. Ensure all of the following commands are installed - ${*}"
      exit 1
    fi
  done
}

get_bitwarden_os() {
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "${os}" in
    cygwin_nt*) goos="windows" ;;
    linux)
      if command -v termux-info >/dev/null 2>&1; then
        goos=android
      else
        goos=linux
      fi
      ;;
    mingw*) goos="windows" ;;
    msys_nt*) goos="windows" ;;
    darwin*) goos="macos" ;;
    *) goos="${os}" ;;
  esac
  printf '%s' "${goos}"
}

unarchive() {
	tarball="${1}"
	case "${tarball}" in
    *.tar.gz | *.tgz) tar -xzf "${tarball}" ;;
    *.tar) tar -xf "${tarball}" ;;
    *.zip) unzip -- "${tarball}" ;;
    *)
      print_colored red bold "Error: Unknown archive format for ${tarball}."
      return 1
      ;;
	esac
}

print_colored() {
  case "$1" in
    black) color="30" ;;
    red) color="31" ;;
    green) color="32" ;;
    yellow) color="33" ;;
    blue) color="34" ;;
    magenta) color="35" ;;
    cyan) color="36" ;;
    white) color="37" ;;
    *) echo "Unknown color: $1"; return 1 ;;
  esac

  shift
  while [ "$#" -gt 1 ]; do
    case "$1" in
      bold) color="${color};1" ;;
      italic) color="${color};3" ;;
      underline) color="${color};4" ;;
      dim) color="${color};2" ;;
      *) echo "Unknown option: $1"; return 1 ;;
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

main "${@}"
