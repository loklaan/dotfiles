#!/usr/bin/env zsh

#|-----------------------------------------------------------------------------|
#| Cool greeting                                                               |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Provides a welcome message, shell tips, and a tmux attach prompt for        |
#| interactive shells.                                                         |
#|                                                                             |
#|-----------------------------------------------------------------------------|

source "${HOME}/.local/lib/term-colour.sh"

message_string_decorations=("✨ 🔮 ✨" "🕒 🧠 🕒" "💥 ✌️ 💥" "☔️ 🐳 ☔️" "🌟 🌙 🌟" "⏰ 💡 ⏰" "⚡️ 🤘 ⚡️" "🌨️ 🐋 🌨️" "🔥 🤙 🔥" "⏳ 💭 ⏳" "🌈 🙌 🌈" "🍀 💪 🍀" "🌞 🤞 🌞" "🍁 🤟 🍁")
message_string_tmux_session_found="➤ tmux session(s) found"
message_string_attach_prompt="  wanna attach? y/N: "
message_string_welcomes=("hold on to ya butts!" "how is your POSTURE lochlan?" "i wonder if you drink enough water dude" "srsly did you hydrate sufficiently?" "CONTRABAND, CONTRABAND, CONTRABAND" "have you tried turning it off and on again" "let's not fall into the rabbit hole of typescript golfin'" "bug free code? more like cug bree fode" "remember, rome wasn't built in a day and actually they abandoned romejs thats pretty sad" "why didn't you pursue botany instead haha" "you're slouchin' in that chair arent cha?" "UNACCEPTAABLLLLLE" "welcome, bunny boi!")
message_string_tips=("Ctrl-T: fuzzy-pick a file and insert its path at the cursor (try: micro <Ctrl-T>)" "micro **<Tab>: fzf path completion, pick a file and it fills in" "Ctrl-R: fuzzy search your shell history")

random_from() {
  local -a from=("$@")
  REPLY=${from[RANDOM % ${#from[@]} + 1]}
}

welcome_message() {
  local decoration welcome
  random_from "${message_string_decorations[@]}"
  decoration=$REPLY
  random_from "${message_string_welcomes[@]}"
  welcome=$REPLY
  print -r -- "$decoration    $welcome    $decoration"
}

tip_message() {
  random_from "${message_string_tips[@]}"
  color_print magenta "tip: $REPLY"
}

greeting() {
  welcome_message
  tip_message
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
  # Exclude IDE / embedded-app terminals — they should not auto-attach to tmux, ever.
  [[ "${TERMINAL_EMULATOR:-}" == *"JetBrains"* ]] && return 1
  [[ "${TERM_PROGRAM:-}" == *"vscode"* ]] && return 1
  return 0
}

resume_tmux_prompt() {
  color_printf magenta "$message_string_tmux_session_found\n"
  read -k 1 "?$message_string_attach_prompt" tmux_prompt_reply
  echo  # newline after input

  # throw if we didn't reply yes
  if [[ "$tmux_prompt_reply" != 'y' ]]; then
    return 1
  fi
}
