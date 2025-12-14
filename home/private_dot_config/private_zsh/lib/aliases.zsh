source "$ZSH_CONFIG_DIR/lib/ssh.zsh"

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

tmux () {
   if [ "$#" -eq 0 ]; then
     command tmux new-session -A -s 'main-session'
   else
     command tmux "$@"
   fi
}
