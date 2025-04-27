################################################################
#                           ~ Magic ~                          #
################################################################

#|-------------------------------|#
#| DEBUG TERM PERFORMANCE
#|-------------------------------|#
PROFILE_STARTUP=false # When true, the profile will be profiled.
if [[ "$PROFILE_STARTUP" == true ]]; then
    zmodload zsh/zprof
fi

#|------------------------------------------------------------|#
#| Reset terminal text
#|------------------------------------------------------------|#
clear && source "$HOME/.zshrc.d/lib/term.zsh"
clear && reset_cursor && cursor_disable

#|------------------------------------------------------------|#
#| Integrate with terminal
#|------------------------------------------------------------|#
[ -f "$HOME/.zshrc.d/integrations.zsh" ] && \
  source "$HOME/.zshrc.d/integrations.zsh"

#|------------------------------------------------------------|#
#| Add env-specific tooling/configuration
#|------------------------------------------------------------|#
[ -f "$HOME/.zshrc.d/env.zsh" ] && \
  source "$HOME/.zshrc.d/env.zsh"

#|------------------------------------------------------------|#
#| Drop into tmux if it's up
#|------------------------------------------------------------|#
if (tmux has-session 2> /dev/null && [[ -z "$TMUX" ]]); then
	if resume_tmux_prompt; then
		tmux new-session -A -s "main-session"
	fi
fi

#|------------------------------------------------------------|#
#| Cute lochlanness
#|------------------------------------------------------------|#
cursor_disable && loading_message

#|------------------------------------------------------------|#
#| zplug
#|------------------------------------------------------------|#
export ZPLUG_HOME="$HOME/.zshrc.d/zplug"
export ZPLUG_LOG_LOAD_SUCCESS=false
export ZPLUG_LOG_LOAD_FAILURE=false
source $ZPLUG_HOME/init.zsh

#|--------------------------------|#
#| Prompt plugins
zplug "~/.zshrc.d/plugins/iterm2", from:local, use:"*.plugin.zsh", if:"[[ $OSTYPE == *darwin* ]]"
zplug "~/.zshrc.d/plugins/ghostty", from:local, use:"*.plugin.zsh"
# TODO: Migrate off of zplug (it's abandoned) - see https://github.com/mattmc3/zsh_unplugged
zplug "~/.zshrc.d/plugins/zsh-autosuggestions", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/zsh-completions", from:local, use:"*.plugin.zsh"
# TODO: Migrate history to https://atuin.sh/
zplug "~/.zshrc.d/plugins/zsh-syntax-highlighting", from:local, use:"*.plugin.zsh", defer:2 # Should be loaded 2nd last
zplug "~/.zshrc.d/plugins/zsh-history-substring-search", from:local, use:"*.plugin.zsh", defer:3 # Should be loaded last
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
zplug "~/.zshrc.d/plugins/zsh-async", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/fzf", from:local, use:"shell/*.zsh"
# TODO: Fork this to get complete control over experience (e.g. quick git branch info)
#       Or better yet, switch to https://starship.rs/guide/
zplug "~/.zshrc.d/plugins/pure", from:local, use:"pure.zsh", as:theme
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/z", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/gpg-agent", from:local, use:"*.plugin.zsh", lazy:true
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/git", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/emoji", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/npm", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/deno", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/yarn", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/docker", from:local, use:"*.plugin.zsh"
zplug "~/.zshrc.d/plugins/oh-my-zsh/plugins/macos", from:local, use:"*.plugin.zsh", if:"[[ $OSTYPE == *darwin* ]]"
zplug "~/.zshrc.d/plugins/oh-my-zsh/lib", from:local, use:"clipboard.zsh"
zplug "~/.zshrc.d/plugins/oh-my-zsh/lib", from:local, use:"completion.zsh"

#|--------------------------------|#
#| Check for uninstalled plugins

# Is this needed?
#echo "\n\e[1;33;40mChecking zplug plugin state...\e[0;37;40m"
#if ! zplug check --verbose; then
#  printf "Install? [y/N]: "
#  if read -q; then
#    echo; zplug install
#  fi
#fi

#|--------------------------------|#
#| Source plugins

zplug load

#|--------------------------------|#
#| Setup completions

autoload -Uz compinit; compinit # The completion.zh plugin handles bashcompinit.

if typeset -f _add_env_completions > /dev/null; then
  _add_env_completions
fi

zstyle ':completion:*' completer _complete _ignored
zstyle ':completion:*' format 'Completing %d...'
zstyle ':completion:*' group-name ''
zstyle :compinstall filename "$HOME/.zshrc"

#|------------------------------------------------------------|#
#| History setup
#|------------------------------------------------------------|#
#| TODO: Migrate history provider to https://atuin.sh/
[ -z "$HISTFILE" ] && HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=10000
setopt extended_history       # record timestamp of command in HISTFILE
setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_dups       # ignore duplicated commands history list
setopt hist_ignore_space      # ignore commands that start with space
setopt hist_verify            # show command with history expansion to user before running it
setopt inc_append_history     # add commands to HISTFILE in order of execution
setopt share_history          # share command history data

#|------------------------------------------------------------|#
#| Load in alias
#|------------------------------------------------------------|#
source $HOME/.aliases

#|------------------------------------------------------------|#
#| Final cute lochlanness
#|------------------------------------------------------------|#
welcome_message && cursor_enable

#|-------------------------------|#
#| DEBUG TERM PERFORMANCE
#|-------------------------------|#
if [[ "$PROFILE_STARTUP" == true ]]; then
     zprof
fi
