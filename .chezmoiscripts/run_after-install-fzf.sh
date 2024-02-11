#!/bin/bash

set -o errexit
set -o nounset

FZF_INSTALL="$HOME/.zsh/plugins/fzf/install"
if [[ -f $FZF_INSTALL ]]; then
  bash "$FZF_INSTALL"
fi

exit 0
