#!/usr/bin/env bash
set -euo pipefail

# Ensure zplug log directory exists — the chezmoi external archive doesn't
# include it, but zplug's flock tries to open log files before checking
# whether logging is disabled.
mkdir -p "${HOME}/.config/zsh/zplug/log"
