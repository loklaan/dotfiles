#!/usr/bin/env zsh
#
# Guards the precmd hook in
# home/private_dot_config/private_zsh/init/terminal-restore.zsh: which command
# lines trigger a restore, and what the restore does to a real terminal.
#
#   zsh tests/terminal-restore.test.zsh
#
# TERM_RESTORE_HOOK=<file> runs it against another revision of the hook.

emulate -R zsh

ROOT=${0:A:h:h}
HOOK=${TERM_RESTORE_HOOK:-$ROOT/home/private_dot_config/private_zsh/init/terminal-restore.zsh}
integer failures=0

fail() {
  print -ru2 -- "FAIL: $*"
  (( ++failures ))
}

source "$HOOK"

#|------------------------------------------------------------|#
#| Which command lines count as a remote session
#|
restores=(
  'cw for-tasks'
  'cw for-tasks tmux'
  'cw for-tasks claude /home/coder/dev/me/dotfiles'
  'cw connect for-tasks'
  'cw connect for-tasks-2 ccyolo'
  'cw tmux for-tasks'
  'cw -L 3000:127.0.0.1:3000 for-tasks'
  'cw --remote-forward 3845:127.0.0.1:3845 for-tasks'
  'FOO=1 cw for-tasks'
  '~/.local/bin/cw for-tasks'
  'ssh coder.for-tasks'
)
quiet=(
  'cw'
  'cw --help'
  'cw --help | less'
  'cw help'
  'cw for-tasks --help'
  'cw connect'
  'cw connect --help'
  'cw connect for-tasks vscode'
  'cw for-tasks cursor'
  'cw tmux'
  'cw tmux --help'
  'cw fleet --include-local update'
  'cw migrate'
  'cw completion zsh > _cw'
  'ls -la'
)
for line in $restores; do
  _term_restore_is_remote_launcher "$line" || fail "no restore after: $line"
done
for line in $quiet; do
  ! _term_restore_is_remote_launcher "$line" || fail "restore after: $line"
done

#|------------------------------------------------------------|#
#| What the restore does to a real terminal
#|
#| Each case runs in its own 80x24 pane of a private tmux server,
#| so the user's tmux is never touched.
#|
if (( ! $+commands[tmux] )); then
  print "skip: tmux not on PATH, terminal checks not run"
else
  # `command` skips the user's rm/tmux aliases and functions, which ~/.zshenv
  # can load even into this non-interactive shell.
  sock="terminal-restore-test-$$"
  tm() { command tmux -L "$sock" -f /dev/null "$@"; }
  tm new-session -d -s t -x 80 -y 24 'sleep 300'
  sock_path=$(tm display -p '#{socket_path}')
  trap 'tm kill-server 2>/dev/null; command rm -f -- "$sock_path"' EXIT

  # run_pane <name> <zsh code>: run the code in a fresh pane with the hook
  # loaded, then wait until the pane prints END.
  run_pane() {
    local name=$1 code="source ${(q)HOOK}; $2; print END; sleep 300" i
    tm new-window -d -t t: -n "$name" "TERM=screen-256color zsh -fc ${(qq)code}"
    for (( i = 0; i < 100; i++ )); do
      [[ "$(tm capture-pane -p -t "t:$name")" == *END* ]] && return 0
      sleep 0.05
    done
    fail "$name: pane never printed END"
    return 1
  }
  screen_lines() { print -r -- "${(j:|:)${(@f)$(tm capture-pane -p -t "t:$1")}}"; }

  # A full-screen app that came and went leaves a saved cursor at the top.
  # A bare 1049l jumps back there, so the prompt lands on earlier output.
  stale='printf "\e[?1049h\e[?1049l"; print -l one two three'

  if run_pane quiet "$stale; _term_restore_preexec 'cw --help'; true; _term_restore_precmd"; then
    got=$(screen_lines quiet)
    [[ $got == 'one|two|three|END' ]] || fail "cw --help: screen disturbed: $got"
  fi

  if run_pane clean "$stale; _term_restore_preexec 'cw for-tasks'; true; _term_restore_precmd"; then
    got=$(screen_lines clean)
    [[ $got == 'one|two|three||'*'remote session ended||END' ]] ||
      fail "clean logout: cursor moved or notice missing: $got"
  fi

  # A dropped session leaves the remote's alternate screen and mouse on.
  if run_pane dropped "print BEFORE; printf '\e[?1049h\e[?1002h\e[?1006h'; print 'remote tmux'; _term_restore_preexec 'cw for-tasks'; (exit 255); _term_restore_precmd"; then
    flags=$(tm display -p -t t:dropped '#{alternate_on}#{mouse_standard_flag}#{mouse_button_flag}#{mouse_any_flag}#{mouse_sgr_flag}')
    [[ $flags == 00000 ]] || fail "dropped session: alt screen/mouse flags left on: $flags"
    got=$(screen_lines dropped)
    [[ $got == BEFORE* && $got == *'unexpectedly (exit 255)'* && $got != *'remote tmux'* ]] ||
      fail "dropped session: primary screen not restored: $got"
  fi
fi

if (( failures )); then
  print -ru2 -- "$failures failure(s)"
  exit 1
fi
print "ok"
