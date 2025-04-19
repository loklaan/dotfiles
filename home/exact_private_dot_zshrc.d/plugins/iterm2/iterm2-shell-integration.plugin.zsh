## iTerm2
if [[ -n "$ITERM_PROFILE" ]]; then
  # Load native integrations
  source /Applications/iTerm.app/Contents/Resources/iterm2_shell_integration.zsh

  # Customise titlebar
  echo -ne "\033]6;1;bg;red;brightness;40\a"
  echo -ne "\033]6;1;bg;green;brightness;42\a"
  echo -ne "\033]6;1;bg;blue;brightness;54\a"
fi
