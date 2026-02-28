#!/usr/bin/env zsh

#|-----------------------------------------------------------------------------|
#| Coder Workspace Management                                                  |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Provides functions for connecting to Coder workspaces via SSH,              |
#| opening them in JetBrains Gateway, or launching Claude Code sessions.       |
#|                                                                             |
#| Requires: coder CLI configured with `coder config-ssh`, jq                 |
#|                                                                             |
#|-----------------------------------------------------------------------------|

#|------------------------------------------------------------|#
#| _coder_is_running
#|
#| Checks whether a named Coder workspace is currently running.
#| Returns 0 if running, 1 otherwise.
#|
_coder_is_running() {
  local name="${1:?workspace name required}"
  coder list -o json 2>/dev/null \
    | jq -e --arg ws "$name" '.[] | select(.name == $ws and .latest_build.status == "running")' \
    >/dev/null 2>&1
}

#|------------------------------------------------------------|#
#| _coder_gpg_setup
#|
#| Prepares GPG agent forwarding for SSH connections to Coder
#| workspaces. Sets _gpg_ssh_opts (array) and _gpg_remote_prefix
#| (string) for use in ssh commands. Silently no-ops if gpg is
#| unavailable locally.
#|
_coder_gpg_setup() {
  _gpg_ssh_opts=()
  _gpg_remote_prefix=""

  command -v gpgconf >/dev/null 2>&1 || return 0

  local local_socket
  local_socket=$(gpgconf --list-dirs agent-extra-socket 2>/dev/null) || return 0
  [[ -n "$local_socket" ]] || return 0

  gpgconf --launch gpg-agent 2>/dev/null

  local fwd="/tmp/.gpg-fwd-${RANDOM}${RANDOM}.sock"
  _gpg_ssh_opts=(-o StreamLocalBindUnlink=yes -R "${fwd}:${local_socket}")
  _gpg_remote_prefix="gpgconf --kill gpg-agent 2>/dev/null; _gs=\$(gpgconf --list-dirs agent-socket 2>/dev/null) && rm -f \"\$_gs\" && ln -sf '${fwd}' \"\$_gs\" && trap 'rm -f \"\$_gs\"' EXIT; "
}

#|------------------------------------------------------------|#
#| coder-workspace (aliased as cw)
#|
#| Connect to a Coder workspace in various modes.
#|
#| Usage:
#|   cw <workspace> [mode] [folder]
#|
#| Arguments:
#|   workspace - workspace name (e.g. for-tasks, for-tasks-2)
#|   mode      - ssh (default), ide, claude, ccyolo
#|   folder    - optional project path on the remote workspace
#|
#| Examples:
#|   cw for-tasks              # SSH into for-tasks
#|   cw for-tasks-2 ide        # Open in IntelliJ project picker
#|   cw for-tasks-2 ide ~/work # Open in IntelliJ at ~/work
#|   cw for-tasks claude       # SSH + Claude Code
#|   cw for-prs ccyolo         # YOLO mode
#|
coder-workspace() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: cw <workspace> [mode] [folder]" >&2
    echo "Modes: ssh (default), ide, claude, ccyolo" >&2
    return 1
  fi

  local ws="$1"
  local mode="${2:-ssh}"
  local folder="$3"

  # Runtime dependency checks
  if ! command -v coder >/dev/null 2>&1; then
    echo "Error: coder CLI not found" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq not found" >&2
    return 1
  fi

  # Verify workspace is running
  if ! _coder_is_running "$ws"; then
    echo "Error: workspace '$ws' is not running" >&2
    echo "Start it with: coder start $ws" >&2
    return 1
  fi

  local host="coder.${ws}"

  _coder_gpg_setup

  case "$mode" in
    ssh)
      local cmd="${_gpg_remote_prefix}"
      [[ -n "$folder" ]] && cmd+="cd ${folder} && "
      cmd+="/usr/bin/zsh -l"
      ssh -t "${_gpg_ssh_opts[@]}" "$host" "$cmd"
      ;;

    ide)
      local uri="jetbrains://gateway/connect#type=ssh&host=${host}"
      if [[ -n "$folder" ]]; then
        local encoded_path
        encoded_path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${folder}', safe=''))")
        uri="${uri}&projectPath=${encoded_path}"
      fi
      echo "Opening JetBrains Gateway: ${ws}${folder:+ at ${folder}}" >&2
      open "$uri"
      ;;

    claude)
      local cmd="${_gpg_remote_prefix}"
      [[ -n "$folder" ]] && cmd+="cd ${folder} && "
      cmd+="otter claude-code"
      ssh -t "${_gpg_ssh_opts[@]}" "$host" "$cmd"
      ;;

    ccyolo)
      local cmd="${_gpg_remote_prefix}"
      [[ -n "$folder" ]] && cmd+="cd ${folder} && "
      cmd+="otter claude-code --dangerously-skip-permissions --permission-mode bypassPermissions --model global.anthropic.claude-opus-4-6-v1"
      ssh -t "${_gpg_ssh_opts[@]}" "$host" "$cmd"
      ;;

    *)
      echo "Error: unknown mode '$mode'" >&2
      echo "Valid modes: ssh, ide, claude, ccyolo" >&2
      return 1
      ;;
  esac
}

alias cw='coder-workspace'

#|------------------------------------------------------------|#
#| Tab completion for coder-workspace / cw
#|
#| Completes workspace names from coder list, modes from a
#| fixed list, and leaves folder open for input.
#|
_coder-workspace() {
  case $CURRENT in
    2) # workspace name
      local -a workspaces
      if command -v coder >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        workspaces=("${(@f)$(coder list -o json 2>/dev/null | jq -r '.[].name')}")
      fi
      _describe 'workspace' workspaces
      ;;
    3) # mode
      local -a modes=('ssh:SSH into workspace' 'ide:Open in JetBrains Gateway' 'claude:SSH + Claude Code' 'ccyolo:SSH + Claude Code YOLO mode')
      _describe 'mode' modes
      ;;
    4) # folder - no completion (remote path)
      _message 'remote folder path (optional)'
      ;;
  esac
}

