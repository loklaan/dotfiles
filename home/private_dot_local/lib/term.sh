#!/usr/bin/env bash

#|-----------------------------------------------------------------------------|
#| Cool greeting                                                               |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Provides terminal greeting functions, decorative messages, cursor          |
#| controls, and tmux session management prompts for interactive shells.      |
#|                                                                             |
#|-----------------------------------------------------------------------------|

source "${HOME}/.local/lib/bash-logging.sh"

message_string_decorations=("✨ 🔮 ✨" "🕒 🧠 🕒" "💥 ✌️ 💥" "☔️ 🐳 ☔️" "🌟 🌙 🌟" "⏰ 💡 ⏰" "⚡️ 🤘 ⚡️" "🌨️ 🐋 🌨️" "🔥 🤙 🔥" "⏳ 💭 ⏳" "🌈 🙌 🌈" "🍀 💪 🍀" "🌞 🤞 🌞" "🍁 🤟 🍁")
message_string_welcome="welcome, bunny boi!"
message_string_tmux_session_found="➤ tmux session(s) found"
message_string_attach_prompt="  wanna attach? y/N: "
message_string_loadings=("hold on to ya butts!" "how is your POSTURE lochlan?" "i wonder if you drink enough water dude" "srsly did you hydrate sufficiently?" "CONTRABAND, CONTRABAND, CONTRABAND" "have you tried turning it off and on again" "let's not fall into the rabbit hole of typescript golfin'" "bug free code? more like cug bree fode" "remember, rome wasn't built in a day and actually they abandoned romejs thats pretty sad" "why didn't you pursue botany instead haha" "you're slouchin' in that chair arent cha?" "UNACCEPTAABLLLLLE")

random_from() {
  local -a from=("$@")
  local index=$(( RANDOM % ${#from[@]} ))
  echo "${from[$index]}"
}

# Gets the cursor position for a string of text, such that the text could be
# center aligned in a terminal's line.
get_cursor_pos_for_horizontal_centering() {
  local terminal_width=$(tput cols)
  local text="${1:?}"
  local text_width=${#text}
  # width of the text area (text and spacing)
  local area_width=$(( text_width + 6 )) # Added extra for odd sized emojis
  # horizontal position of the cursor: column numbering starts at 0
  local hpc=$(( (terminal_width - area_width) / 2 ))
  echo $hpc
}

get_line_number_for_vertical_center() {
  local lines=$(tput lines)
  local line=$(( lines / 2 ))
  echo "$line"
}

clear_line() {
  tput el1
}

reset_cursor() {
  tput cup 0 0
}

cursor_enable() {
  tput cnorm
}

cursor_disable() {
  tput civis
}

print_in_horizontal_center() {
  local text="${1:?}"
  local line="${2:-0}"
  tput cup $line $(get_cursor_pos_for_horizontal_centering "$text")
  printf "$text"
}

print_in_vertical_center() {
  local text="${1:?}"
  local line=$(get_line_number_for_vertical_center)
  print_in_horizontal_center "$text" $line
}

print_middle_decorations() {
  local decoration=$(random_from "${message_string_decorations[@]}")
  print_in_horizontal_center "$decoration    $1    $decoration"
}

print_center_decorations() {
  local decoration=$(random_from "${message_string_decorations[@]}")
  print_in_vertical_center "$decoration    $1    $decoration"
}

welcome_message() {
  clear_line && reset_cursor && \
  print_middle_decorations "$message_string_welcome"
}

#|-------------------------------|#
#| is_interactive_shell
#|
#| A more robust interactive check that also detects IDE/agent background shells.
#| These tools often spawn shells to read environment but aren't truly interactive.
#|
#| Usage:
#|   if is_interactive_shell; then
#|     # Only run in truly interactive shells (not IDE env readers or AI agents)
#|     eval "$(some-slow-tool init)"
#|   fi
#|
#|   is_interactive_shell || return  # Early exit for non-interactive/background shells
#|
is_interactive_shell() {
  # ZSH interactive check
  if [[ -n "$ZSH_VERSION" ]] && [[ ! -o interactive ]]; then
    return 1
  fi
  # Bash interactive check
  if [[ -n "$BASH_VERSION" ]] && [[ $- != *i* ]]; then
    return 1
  fi
  # JetBrains IDEs (IntelliJ, WebStorm, PyCharm, etc.)
  [[ -n "$INTELLIJ_ENVIRONMENT_READER" ]] && return 1
  # VS Code (environment resolver, shell injection, or spawned shell without terminal)
  [[ -n "$VSCODE_RESOLVING_ENVIRONMENT" || -n "$VSCODE_INJECTION" ]] && return 1
  [[ -n "$__CFBundleIdentifier" && "$__CFBundleIdentifier" == *"vscode"* && -z "$TERM_PROGRAM" ]] && return 1
  # Cursor AI agent
  [[ -n "$CURSOR_AGENT" ]] && return 1
  # CI environments (GitHub Actions, generic CI)
  [[ -n "$GITHUB_ACTIONS" || -n "$CI" ]] && return 1
  # Dumb terminal (often used by Emacs, IDE integrations)
  [[ "$TERM" == "dumb" ]] && return 1
  return 0
}

should_attempt_resume_tmux_prompt() {
  # Already in tmux
  [[ -n "$TMUX" ]] && return 1
  # No tmux sessions exist
  ! tmux has-session 2> /dev/null && return 1
  ! is_interactive_shell && return 1
  # Exclude IDE terminals, they should not auto-attach to tmux, ever
  [[ "${TERMINAL_EMULATOR:-}" == *"JetBrains"* ]] && return 1
  [[ "${TERM_PROGRAM:-}" == *"vscode"* ]] && return 1
  return 0
}

resume_tmux_prompt_centered() {
  local center_line=$(get_line_number_for_vertical_center)
  local notice_line=$(( center_line - 1 ))
  local prompt_line=$(( center_line + 1 ))

  clear && reset_cursor && \
  print_in_horizontal_center "$message_string_tmux_session_found" $notice_line

  reset_cursor && cursor_enable && \
  tput cup $prompt_line $(get_cursor_pos_for_horizontal_centering "$message_string_attach_prompt")

  read -n 1 -s -r -p "$message_string_attach_prompt" tmux_prompt_reply 2> /dev/null

  # throw if we didn't reply yes
  if [[ "$tmux_prompt_reply" != 'y' ]]; then
    return 1
  fi
}

resume_tmux_prompt() {
  color_printf magenta "$message_string_tmux_session_found\n"
  read -n 1 -s -r -p "$message_string_attach_prompt" tmux_prompt_reply 2> /dev/null

  # throw if we didn't reply yes
  if [[ "$tmux_prompt_reply" != 'y' ]]; then
    return 1
  fi
}

loading_message() {
  clear && reset_cursor && \
  print_center_decorations "$(random_from "${message_string_loadings[@]}")"
}
