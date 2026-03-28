if (( $+commands[starship] )); then
  export STARSHIP_LOG=error
  eval "$(starship init zsh)"
else
  source "${HOME}/.local/lib/bash-logging.sh"
  color_printf magenta 'starship not found, try running `mise install`'
fi
