#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly LOG_FILE="/tmp/$(basename "$0").${TIMESTAMP}.log"

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
    printf "\033[${color}m%s\033[0m\n" "$1"
  else
    printf "%s\n" "$1"
  fi
}
info() { _print yellow "[INFO] $@" | tee -a "$LOG_FILE" >&2 ; }
warning() { _print yellow "[WARNING] $@" | tee -a "$LOG_FILE" >&2 ; }
error() { _print red "[ERROR] $@" | tee -a "$LOG_FILE" >&2 ; }
fatal() { _print red bold "[FATAL] $@" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

container_id=-1

cleanup() {
  if [ "$container_id" != -1 ]; then
    docker stop "$container_id" &> /dev/null || true
  fi
  rm -f Dockerfile

  _print white dim "Log: $LOG_FILE" >&2
}

parse_args() {
  if [ -z "${DOCKER_HOST-}" ]; then
    warning "DOCKER_HOST is not set. Using default Docker host."
  else
    info "DOCKER_HOST is set: $DOCKER_HOST"
  fi

  if [ -z "${CONFIG_BWS_ACCESS_TOKEN-}" ]; then
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
  parse_args "$@"
  info "Testing end-to-end installation!"

  info "Building Docker image..."
  cat <<EOF > Dockerfile
FROM codercom/enterprise-base:ubuntu-20251006

RUN sudo apt-get update && sudo apt-get install -y curl git sudo dirmngr gpg gpg-agent

#RUN sudo useradd -m -s /bin/bash testuser && echo "testuser:testuser" | sudo chpasswd
#RUN echo "testuser ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/testuser && chmod 440 /etc/sudoers.d/testuser

WORKDIR /home/testuser

#RUN mkdir -p ~/.config/chezmoi && cat <<EOT >> ~/.config/chezmoi/chezmoi.toml
#[data]
#  email = "bunn@lochlan.io"
#  emailWork = "bunn@lochlan.io"
#  signingKey = "~/.ssh/id_rsa.pub"
#  brewprefix = "/usr/local"
#EOT

COPY install.sh .

#USER root
CMD ["/bin/bash", "-c", "bash ./install.sh"]
EOF

  docker build -t dotfiles-test -f Dockerfile .

  info "Running Docker container..."
  container_id=$(timestamp=$(date +%s); echo "dotfiles-test-$timestamp")
  docker run \
    -it --name "$container_id" --rm \
    -e "TERM=xterm-256color" \
    -e "CONFIG_BWS_ACCESS_TOKEN=$CONFIG_BWS_ACCESS_TOKEN" \
    dotfiles-test

  info "Verifying tool installations..."

  tools_to_check=(
    "aws"
    "bws"
    "chezmoi"
    "delta"
    "deno"
    "difft"
    "flyctl"
    "fzf"
    "git-lfs"
    "go"
    "lua"
    "shellcheck"
    "tmux"
  )

  for tool in "${tools_to_check[@]}"; do
    if docker exec "$container_id" bash -c "command -v $tool &> /dev/null"; then
      info "  ✔ $tool is installed."
    else
      error "  ❌ $tool is NOT installed."
      exit 1
    fi
  done

  info "Running chezmoi verify..."
  docker exec "$container_id" bash -c "chezmoi verify"

  info "End-to-end installation test completed successfully!"
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  trap cleanup EXIT
  main "$@"
fi
