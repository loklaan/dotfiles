#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Normalize TMPDIR (strip trailing slash for consistent path construction)
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
readonly LOG_FILE="${TMPDIR}/$(basename "$0").$(date +"%Y%m%d_%H%M%S").log"

#/ Usage: ./install.test.sh
#/ Description: Runs an end-to-end installation test for the dotfiles repository.
#/              Verification occurs in a Docker container.
#/
#/ Environment Variables:
#/   DOCKER_HOST:     Docker host to use for running the container [optional]
#/   CONFIG_BWS_ACCESS_TOKEN:  For authentication—with Bitwarden Secrets
#/
#/ Options:
#/   --help: Display this help message

usage() { grep '^#/' "$0" | cut -c4- ; }
relative_time() {
  local timestamp="$1"

  # Parse timestamp - extract seconds and milliseconds
  local seconds_part="${timestamp%.*}"
  local ms_part="${timestamp##*.}"

  # If no milliseconds provided, set to 0
  if [ "$ms_part" = "$timestamp" ]; then
    ms_part="0"
  fi

  # Convert timestamp to epoch - works on both macOS and Linux
  local timestamp_epoch
  if date -j &>/dev/null 2>&1; then
    # macOS
    timestamp_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$seconds_part" +%s 2>/dev/null)
  else
    # Linux
    timestamp_epoch=$(date -d "$seconds_part" +%s 2>/dev/null)
  fi

  if [ -z "$timestamp_epoch" ]; then
    echo "Invalid timestamp format"
    return 1
  fi

  # Add milliseconds as a fraction
  timestamp_epoch="${timestamp_epoch}.${ms_part}"

  local current_time=$(date +%s.%N)

  # Calculate difference in seconds (with milliseconds)
  local diff=$(echo "$current_time - $timestamp_epoch" | bc)

  # Remove decimal part for comparisons
  local diff_int=${diff%.*}

  if [ -z "$diff_int" ] || [ "$diff_int" = "" ]; then
    diff_int=0
  fi

  if [ "$diff_int" -lt 0 ] 2>/dev/null; then
    diff_int=$((diff_int * -1))
    local prefix="-"
  else
    local prefix="+"
  fi

  if [ "$diff_int" -lt 1 ]; then
    # Show milliseconds
    local ms=$(echo "$diff * 1000" | bc | cut -d. -f1)
    echo "$prefix${ms} ms"
  elif [ "$diff_int" -lt 60 ]; then
    echo "$prefix${diff_int} second$([ "$diff_int" -ne 1 ] && echo 's')"
  elif [ "$diff_int" -lt 3600 ]; then
    local minutes=$((diff_int / 60))
    echo "$prefix${minutes} minute$([ $minutes -ne 1 ] && echo 's')"
  elif [ "$diff_int" -lt 86400 ]; then
    local hours=$((diff_int / 3600))
    echo "$prefix${hours} hour$([ $hours -ne 1 ] && echo 's')"
  elif [ "$diff_int" -lt 2592000 ]; then
    local days=$((diff_int / 86400))
    echo "$prefix${days} day$([ $days -ne 1 ] && echo 's')"
  else
    local months=$((diff_int / 2592000))
    echo "$prefix${months} month$([ $months -ne 1 ] && echo 's')"
  fi
}
relative_time_from_start() { relative_time $TIMESTAMP; }
_printf() {
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

  supported_colors=$(tput colors 2>/dev/null || echo 0)
  if [ -n "$supported_colors" ] && [ "$supported_colors" -gt 8 ]; then
    printf "\033[${color}m%s\033[0m" "$1"
  else
    printf "%s" "$1"
  fi
}
_print() { (_printf magenta dim "test_e2e"; _printf white dim " $@"; _printf magenta dim " $(relative_time_from_start)"; printf "\n";) | tee -a "$LOG_FILE" >&2 ; }
info() { (_printf magenta "test_e2e"; _printf cyan " info"; printf " %s" "$@"; _printf magenta " $(relative_time_from_start)"; printf "\n";) | tee -a "$LOG_FILE" >&2 ; }
warning() { (_printf magenta "test_e2e"; _printf yellow " warn"; printf " %s" "$@"; _printf magenta " $(relative_time_from_start)"; printf "\n";) | tee -a "$LOG_FILE" >&2 ; }
error() { (_printf magenta "test_e2e"; _printf red " error"; printf " %s" "$@"; _printf magenta " $(relative_time_from_start)"; printf "\n";) | tee -a "$LOG_FILE" >&2 ; }
fatal() { (_printf magenta "test_e2e"; _printf red bold " fatal"; printf " %s" "$@"; _printf magenta " $(relative_time_from_start)"; printf "\n";) | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

image_base_id=-1
image_dotfiles_id=-1
image_withpackages_id=-1
container_withbase_id=-1
container_withdotfiles_id=-1

cleanup() {
#  if [ "$image_base_id" != -1 ]; then
#    docker rmi "$image_base_id" &> /dev/null || true
#    _print "Clean: Removed docker image \"$image_base_id\"" >&2
#  fi
#  if [ "$image_dotfiles_id" != -1 ]; then
#    docker rmi "$image_dotfiles_id" &> /dev/null || true
#    _print "Clean: Removed docker image \"$image_dotfiles_id\"" >&2
#  fi
  if [ "$image_withpackages_id" != -1 ]; then
    docker rmi "$image_withpackages_id" &> /dev/null || true
    _print "Clean: Removed docker image \"$image_withpackages_id\"" >&2
  fi

  if [ "$container_withbase_id" != -1 ]; then
    docker stop "$container_withbase_id" &> /dev/null || true
    docker remove "$container_withbase_id" &> /dev/null || true
    _print "Clean: Removed docker container \"$container_withbase_id\"" >&2
  fi
  if [ "$container_withdotfiles_id" != -1 ]; then
    docker stop "$container_withdotfiles_id" &> /dev/null || true
    docker remove "$container_withdotfiles_id" &> /dev/null || true
    _print "Clean: Removed docker container \"$container_withdotfiles_id\"" >&2
  fi

  if [ -f Dockerfile ]; then
    rm -f Dockerfile
    _print "Clean: Deleted \"Dockerfile\"" >&2
  fi

  _print "Log: $LOG_FILE" >&2
}

parse_args() {
  if [ -z "${DOCKER_HOST-}" ]; then
    warning "DOCKER_HOST is not set. Using default Docker host."
  else
    info "DOCKER_HOST is set: $DOCKER_HOST"
  fi

  if [ -z "${CONFIG_BWS_ACCESS_TOKEN-}" ] || [ -z "${GITHUB_TOKEN-}" ]; then
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
        fatal "Error: Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  info "Testing end-to-end installation!"
  parse_args "$@"

  info "Building Docker image..."
  cat <<EOF > Dockerfile
FROM codercom/enterprise-base:ubuntu-20251006

RUN sudo apt-get update && sudo apt-get install --no-install-recommends -y curl git sudo dirmngr gpg gpg-agent zsh

WORKDIR /home/coder

RUN mkdir -p /home/coder/.config/chezmoi && cat <<EOT >> /home/coder/.config/chezmoi/chezmoi.toml
[data]
  email = "bunn@lochlan.io"
  emailWork = "lochlan@canva.com"
  signingKey = "~/.ssh/id_rsa.pub"
  brewprefix = "/usr/local"
EOT

COPY install.sh .

CMD ["/bin/bash", "-c", "bash ./install.sh"]
EOF

  docker build -t dotfiles-test -f Dockerfile .

  info "Running dotfiles install.sh in Docker container..."
  container_withbase_id=$(timestamp=$(date +%s); echo "dotfiles-container-base-$timestamp")
  docker run \
    -it --name "$container_withbase_id" \
    -e "GITHUB_TOKEN=$GITHUB_TOKEN" \
    -e "TERM=xterm-256color" \
    -e "CONFIG_BWS_ACCESS_TOKEN=$CONFIG_BWS_ACCESS_TOKEN" \
    dotfiles-test
  info "  ✔ Dotfiles install.sh run successfully."

  image_dotfiles_id=dotfiles-test-success
  info "Committing successful dotfiles installation as '$image_dotfiles_id'..."
  docker commit "$container_withbase_id" "$image_dotfiles_id" > /dev/null

  info "Running install-my-packages in Docker container..."
  container_withdotfiles_id=$(timestamp=$(date +%s); echo "dotfiles-container-withdotfiles-$timestamp")
  docker run \
    -it --name "$container_withdotfiles_id" \
    -e "GITHUB_TOKEN=$GITHUB_TOKEN" \
    "$image_dotfiles_id" \
    zsh -c ".local/bin/install-my-packages"

  info "  ✔ Command install-my-packages run successfully."

  image_withpackages_id=withpackages-test-success
  info "Committing successful packages installation as '$image_withpackages_id'..."
  docker commit "$container_withdotfiles_id" "$image_withpackages_id" > /dev/null

  info "Verifying tool installations..."
  tools_to_check=(
    "bws"
    "chezmoi"
    "delta"
    "deno"
    "difft"
    "flyctl"
    "fzf"
    "go"
    "lua"
    "node"
    "rustup"
    "shellcheck"
  )
  for tool in "${tools_to_check[@]}"; do
    if docker run -e "GITHUB_TOKEN=$GITHUB_TOKEN" -it --rm "$image_withpackages_id" bash -c "command -v $tool &> /dev/null"; then
      info "  ✔ $tool is installed."
    else
      error "  ❌ $tool is NOT installed."
      exit 1
    fi
  done

  info "Running chezmoi verify..."
  docker run -e "GITHUB_TOKEN=$GITHUB_TOKEN" -it --rm "$image_withpackages_id" bash -c "chezmoi verify"
  info "  ✔ Verified all dotfiles."

  info "End-to-end installation test completed successfully!"
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  trap cleanup EXIT
  _print "Starting $(basename "$0") script."
  main "$@"
fi
