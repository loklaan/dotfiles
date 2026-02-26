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

  case "$mode" in
    ssh)
      if [[ -n "$folder" ]]; then
        ssh -t "$host" "cd ${folder} && exec /usr/bin/zsh -l"
      else
        ssh -t "$host" "exec /usr/bin/zsh -l"
      fi
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
      local cmd="otter claude-code"
      if [[ -n "$folder" ]]; then
        cmd="cd ${folder} && ${cmd}"
      fi
      ssh -t "$host" "$cmd"
      ;;

    ccyolo)
      local cmd="otter claude-code --dangerously-skip-permissions --permission-mode bypassPermissions --model global.anthropic.claude-opus-4-6-v1"
      if [[ -n "$folder" ]]; then
        cmd="cd ${folder} && ${cmd}"
      fi
      ssh -t "$host" "$cmd"
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

compdef _coder-workspace coder-workspace
compdef _coder-workspace cw
