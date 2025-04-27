#|------------------------------------------------------------|#
#| Cool greeting
#|------------------------------------------------------------|#

cutes=("✨ 🔮 ✨" "🕒 🧠 🕒" "💥 ✌️ 💥" "☔️ 🐳 ☔️" "🌟 🌙 🌟" "⏰ 💡 ⏰" "⚡️ 🤘 ⚡️" "🌨️ 🐋 🌨️" "🔥 🤙 🔥" "⏳ 💭 ⏳" "🌈 🙌 🌈" "🍀 💪 🍀" "🌞 🤞 🌞" "🍁 🤟 🍁");
cute_message_to_me="welcome, ya cutie!"
cute_tmux_prompt_notice="OH!! there's a tmux runnin'!"
cute_prompt="Wanna? y/N: "
expressions=("hold on to ya butts!" "how is your POSTURE lochlan?" "i wonder if you drink enough water dude" "srsly did you hydrate sufficiently?" "CONTRABAND, CONTRABAND, CONTRABAND" "have you tried turning it off and on again" "let's not fall into the rabbit hole of typescript golfin'" "bug free code? more like cug bree fode" "remember, rome wasn't built in a day and actually they abandoned romejs thats pretty sad" "why didn't you pursue botany instead haha" "you're slouchin' in that chair arent cha?" "UNACCEPTAABLLLLLE")

random_from () {
  local from=( $@ )
  val=${from[$(($RANDOM % ${#from[@]} + 1 ))]}
  echo $val
}

# Gets the cursor position for a string of text, such that the text could be
# center aligned in a terminal's line.
get_cursor_pos_for_horizontal_centering () {
  local terminal_width=$(tput cols)
  local text="${1:?}"
  local text_width=${#text}
  # width of the text area (text and spacing)
  local area_width=$(( text_width + 6 )) # Added extra for odd sized emojis
  # horizontal position of the cursor: column numbering starts at 0
  local hpc=$(( (terminal_width - area_width) / 2 ))
  echo $hpc
}

get_line_number_for_vertical_center () {
  local lines=$(tput lines)
  local line=$(( lines / 2 ))
  echo "$line"
}

clear_line () {
  tput el1
}

reset_cursor () {
  tput cup 0 0
}

cursor_enable () {
  tput cnorm
}

cursor_disable () {
  tput civis
}

print_in_horizontal_center () {
  local text="${1:?}"
  local line="${2:-0}"
  tput cup $line $(get_cursor_pos_for_horizontal_centering $text)
  printf "$text"
}

print_in_vertical_center () {
  local text="${1:?}"
  local line=$(get_line_number_for_vertical_center)
  print_in_horizontal_center "$text" $line
}

print_middle_cuteness () {
  local cute=$(random_from $cutes)
  print_in_horizontal_center "$cute    $1    $cute"
}

print_center_cuteness () {
  local cute=$(random_from $cutes)
  print_in_vertical_center "$cute    $1    $cute"
}

welcome_message () {
  clear_line && reset_cursor && \
  print_middle_cuteness "$cute_message_to_me"
}

resume_tmux_prompt () {
  local center_line=$(get_line_number_for_vertical_center)
  local notice_line=$(( center_line - 1 ))
  local prompt_line=$(( center_line + 1 ))

  clear && reset_cursor && \
  print_in_horizontal_center "$cute_tmux_prompt_notice" $notice_line

  reset_cursor && cursor_enable && \
  tput cup $prompt_line $(get_cursor_pos_for_horizontal_centering "$cute_prompt") && \
  read -qk "tmux_prompt_reply?$cute_prompt" 2> /dev/null

  # throw if we didn't reply yes
  if [[ "$tmux_prompt_reply" != 'y' ]]; then
    return 1
  fi
}

loading_message () {
  clear && reset_cursor && \
  print_center_cuteness "$(random_from $expressions)"
}
