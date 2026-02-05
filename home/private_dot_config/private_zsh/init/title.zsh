#|-----------------------------------------------------------------------------|
#| INIT MODULE: Title                                                          |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Purpose:                                                                    |
#|   Sets terminal window/tab title dynamically based on context.              |
#|                                                                             |
#| Responsibilities:                                                           |
#|   - Update title on directory change via precmd hook                        |
#|   - Show hostname when in SSH session                                       |
#|   - Show tmux session name when inside tmux                                 |
#|                                                                             |
#|-----------------------------------------------------------------------------|

#|------------------------------------------------------------|#
#| _set_terminal_title
#|
#| Updates the terminal title with contextual information.
#| Format: [host] session | ~/path
#|   - host: only shown in SSH sessions
#|   - session: tmux session name, only when inside tmux
#|   - path: current working directory with ~ substitution
#|
_set_terminal_title() {
  local title=""
  local dir="${PWD/#$HOME/~}"

  # Add hostname if in SSH session
  if [[ -n "$SSH_TTY" || -n "$SSH_CONNECTION" ]]; then
    title="[${HOST%%.*}] "
  fi

  # Add tmux session name if inside tmux
  if [[ -n "$TMUX" ]]; then
    local session
    session=$(tmux display-message -p '#S' 2>/dev/null)
    if [[ -n "$session" ]]; then
      title+="${session} | "
    fi
  fi

  title+="$dir"

  # OSC 2: Set window title
  print -Pn "\e]2;${title}\a"
}

precmd_functions+=(_set_terminal_title)
