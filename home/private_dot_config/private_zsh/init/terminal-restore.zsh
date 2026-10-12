#!/usr/bin/env zsh

#|-----------------------------------------------------------------------------|
#| INIT MODULE: Terminal Restore                                               |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Purpose:                                                                    |
#|   Restore a sane local terminal after a remote session returns control,     |
#|   and announce why control came back.                                       |
#|                                                                             |
#| Why this exists:                                                            |
#|   A remote tmux/vim enables xterm private modes (mouse tracking, bracketed  |
#|   paste, alt-screen). On a clean logout the remote disables them; but when  |
#|   the link dies abruptly (laptop hibernation, network change) it never      |
#|   gets the chance, so the LOCAL terminal is left in mouse-reporting mode    |
#|   and spews escape codes like <35;40;12M on every mouse move. OpenSSH       |
#|   restores POSIX termios on exit but NOT these application-level modes, and |
#|   ssh_config has no disconnect hook.                                        |
#|                                                                             |
#| Why a prompt hook (not an ssh wrapper):                                     |
#|   The event we care about is "control returned to my local prompt in a      |
#|   possibly-dirty state" — which is exactly what precmd fires on. Hooking    |
#|   here means ONE implementation covers ssh, cw, mosh, et, or a crashed      |
#|   local TUI, with zero per-tool wrappers to maintain. preexec records the   |
#|   command; precmd cleans up only when that command was a remote launcher.   |
#|   One-shot ssh commands stay quiet unless -t forces a terminal.             |
#|                                                                             |
#|-----------------------------------------------------------------------------|

typeset -g _TERM_RESTORE_PENDING=""
typeset -g _TERM_RESTORE_CMD=""

#|------------------------------------------------------------|#
#| _term_restore_emit
#|
#| Reset the terminal modes a dropped remote session may have
#| left enabled. Named terminfo capabilities resolve per-terminal
#| via tput; the mouse / bracketed-paste disables and the DECSTR
#| soft reset have no terminfo capability, so they are literal —
#| the system reset string (tput rs2) emits these raw too.
#| Preserves scrollback (no clear), unlike `reset`.
#|
#| Leaving the alternate screen is literal too, NOT `tput rmcup`.
#| Its 1049l restores the saved cursor even when already on the
#| primary screen (tmux, and Ghostty following xterm), so the
#| cursor jumps to wherever the last full-screen app started and
#| the next prompt lands on the command's output, clearing it.
#| DECSC/DECRC (ESC 7 / ESC 8) around it make that a no-op there.
#|
_term_restore_emit() {
  printf '\e7\e[?1049l\e8'  # leave alternate screen, cursor kept (see above)
  tput rmkx 2>/dev/null   # exit keypad-transmit mode
  tput cnorm 2>/dev/null  # show cursor
  tput sgr0 2>/dev/null   # reset colours / attributes
  printf '\033[!p'        # DECSTR soft reset (no terminfo cap)
  printf '\033[?1002l\033[?1003l\033[?1006l\033[?2004l'  # disable mouse + bracketed paste (no terminfo caps)
}

#|------------------------------------------------------------|#
#| _term_restore_is_remote_launcher
#|
#| True when the command line launched a remote/full-screen
#| session whose abrupt exit can leave the terminal dirty. Matches
#| the program word, tolerating leading env assignments. cw and ssh
#| count only when attaching, so help and one-shot ssh stay quiet.
#|
_term_restore_is_remote_launcher() {
  local -a words=("${(@Q)${(z)1}}")
  while [[ "${words[1]}" == *=* ]]; do shift words; done  # skip leading VAR=val assignments
  case "${words[1]:t}" in
    cw) _term_restore_cw_attaches "${(@)words[2,-1]}" ;;
    ssh) _term_restore_ssh_attaches "${(@)words[2,-1]}" ;;
    mosh|et|sshrc|autossh) return 0 ;;
    *) return 1 ;;
  esac
}

#|------------------------------------------------------------|#
#| _term_restore_ssh_attaches
#|
#| True for a destination without a remote command, or with -t.
#| Forward-only, control, query and background modes never attach.
#| Stop at shell operator tokens, not operator characters inside
#| a quoted remote command (which arrives as one unquoted word).
#|
_term_restore_ssh_attaches() {
  local arg flags flag dest="" tty="" skip="" end_options=""
  for arg in "$@"; do
    case "$arg" in
      ';'|'|'|'||'|'&&'|'&'|'|&') break ;;
    esac
    [[ "$arg" =~ '^[0-9]*[<>]' ]] && break
    if [[ -n "$skip" ]]; then
      skip=""
      continue
    fi
    if [[ -z "$end_options" ]]; then
      case "$arg" in
        --) end_options=1; continue ;;
        -?*)
          flags="${arg[2,-1]}"
          while [[ -n "$flags" ]]; do
            flag="${flags[1]}"
            flags="${flags[2,-1]}"
            case "$flag" in
              N|W|O|G|V|Q|f) return 1 ;;
              t) tty=1 ;;
              B|b|c|D|E|e|F|I|i|J|L|l|m|o|P|p|R|S|w)
                [[ -n "$flags" ]] || skip=1  # attached value or next word
                break ;;
            esac
          done
          continue ;;
      esac
    fi
    # After the destination, this word and the rest belong to the remote command.
    if [[ -n "$dest" ]]; then
      [[ -n "$tty" ]]; return
    fi
    dest=1
  done
  [[ -n "$dest" && -z "$skip" ]]
}

#|------------------------------------------------------------|#
#| _term_restore_cw_attaches
#|
#| True when cw's arguments hand the terminal to a workspace:
#| `tmux`, or `connect` / a bare workspace in an SSH terminal
#| mode (usesSshTerminal in cw). Help, fleet, migrate, completion
#| and app modes like vscode never do. Parsing stops at the first
#| shell operator, so `cw --help | less` still reads as help.
#|
_term_restore_cw_attaches() {
  local -a pos
  local arg mode skip=""
  for arg in "$@"; do
    if [[ -n "$skip" ]]; then
      skip=""
      continue
    fi
    case "$arg" in
      *[\;\&\|\<\>]*) break ;;                           # end of the cw command
      --help|-h) return 1 ;;
      -L|-R|--local-forward|--remote-forward) skip=1 ;;  # value is the next word
      -*) ;;
      *) pos+=("$arg") ;;
    esac
  done
  case "${pos[1]}" in
    ''|help|fleet|migrate|completion) return 1 ;;
    tmux) [[ -n "${pos[2]}" ]]; return ;;
    connect) [[ -n "${pos[2]}" ]] || return 1; mode="${pos[3]:-ssh}" ;;
    *) mode="${pos[2]:-ssh}" ;;
  esac
  case "$mode" in
    ssh|tmux|claude) return 0 ;;
  esac
  return 1
}

#|------------------------------------------------------------|#
#| _term_restore_preexec / _term_restore_precmd
#|
#| preexec records whether the command being run is a remote
#| launcher (and its exit later); precmd, on return to the prompt,
#| restores the terminal and prints a notice when it was.
#|
_term_restore_preexec() {
  if _term_restore_is_remote_launcher "$1"; then
    _TERM_RESTORE_PENDING="1"
    _TERM_RESTORE_CMD="$1"
  else
    _TERM_RESTORE_PENDING=""
    _TERM_RESTORE_CMD=""
  fi
}

_term_restore_precmd() {
  local rc=$?
  [[ -n "$_TERM_RESTORE_PENDING" ]] || return 0
  _TERM_RESTORE_PENDING=""

  [[ -t 1 ]] && _term_restore_emit

  if [[ -t 2 ]]; then
    if (( rc == 0 )); then
      printf '\n  \u279c remote session ended\n\n' >&2
    else
      printf '\n  \u279c remote session ended unexpectedly (exit %d)\n' "$rc" >&2
      printf '    reconnect and `tmux attach` to resume where you left off\n\n' >&2
    fi
  fi
}

preexec_functions+=(_term_restore_preexec)
precmd_functions+=(_term_restore_precmd)
