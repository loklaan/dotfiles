source "$ZSH_CONFIG_DIR/lib/ssh.zsh"

#|------------------------------------------------------------|#
#| SSH & Git Wrapper Functions
#|
#| These functions wrap ssh, scp, and git commands to
#| automatically add SSH keys before execution.
#|
ssh() {
  _ssh_add
  command ssh "$@"
}

scp() {
  _ssh_add
  command scp "$@"
}

git() {
  case $1 in
      push|pull|fetch|clone)
          _ssh_add
          ;;
  esac

  command git "$@"
}

#|------------------------------------------------------------|#
#| Tmux Wrapper Function
#|
#| Wraps tmux to automatically attach to or create a
#| 'main-session' when invoked without arguments.
#|
tmux () {
   if [ "$#" -eq 0 ]; then
     command tmux new-session -A -s 'main-session'
   else
     command tmux "$@"
   fi
}
