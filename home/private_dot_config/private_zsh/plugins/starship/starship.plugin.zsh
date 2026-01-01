if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
else
  source "$ZSH_CONFIG_DIR/lib/color.zsh"
  color_printf magenta 'starship not found, try running `mise install`'
fi
