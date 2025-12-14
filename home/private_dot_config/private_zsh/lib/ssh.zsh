#|------------------------------------------------------------|#
#| SSH Automation
#|
#|  The following setup does the following:
#|   1. Override common ssh enables commands
#|   2. When any of them are used, ssh-add is lazily executed
#|   3. Finally, we start ssh-agent which will enable ssh-add
#|   4. Ensure GPG tty is configured
#|
#|------------------------------------------------------------|#

export _SSH_AGENT_INFO_CACHE=$HOME/.cache/ssh-agent-info

_ssh_add() {
  [ "$SSH_CONNECTION" ] && return

  if [ "$(_is_ssh_agent_active)" = "false" ]; then
    echo "Inactive ssh-agent. Restarting..."
    _ssh_agent
  fi

  local key=$HOME/.ssh/id_rsa

  ssh-add -l >/dev/null || ssh-add $key
}

_is_ssh_agent_active() {
  [ -f $_SSH_AGENT_INFO_CACHE ] && . $_SSH_AGENT_INFO_CACHE >/dev/null

  local ssh_agent_running="$([ "$SSH_AGENT_PID" ] && kill -0 $SSH_AGENT_PID 2>/dev/null && echo "true" || echo "false")"
  local ssh_agent_sock_exists="$([ -S "$SSH_AUTH_SOCK" ] && echo "true" || echo "false" )"

  if [ "$ssh_agent_running" = "false" ] || [ "$ssh_agent_sock_exists" = "false" ]; then
    echo "false";
  else
    echo "true";
  fi
}

_ssh_agent() {
  command -v ssh-agent >/dev/null || return
  [ "$SSH_CONNECTION" ] && return

  if [ "$(_is_ssh_agent_active)" = "false" ]; then
    echo "Setting ssh-agent instance details..."
    mkdir -p "$(dirname "$_SSH_AGENT_INFO_CACHE")"
    local ssh_agent_cmd=$(ssh-agent)
    echo "$ssh_agent_cmd" > "$_SSH_AGENT_INFO_CACHE"
  fi

  eval $(cat "$_SSH_AGENT_INFO_CACHE") >/dev/null
}
