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
#| _coder_preflight
#|
#| Single pre-flight SSH that handles all remote setup for
#| Coder workspace connections. Each module prepares local
#| data, contributes a subshell to the remote script, and
#| parses its results from labeled output lines. The combined
#| script is piped to /bin/sh via stdin.
#|
#| Modules:
#|   GPG      — imports keys, returns socket path for forwarding
#|   Terminfo — installs xterm-ghostty via Homebrew ncurses
#|
#| Outputs (set as side-effects):
#|   _gpg_ssh_opts  — SSH opts for GPG agent reverse tunnel
#|   _term_env      — TERM override for the remote command
#|
_coder_preflight() {
  local host="${1:?host required}"

  _gpg_ssh_opts=()
  _term_env=""

  local script=""
  local gpg_local_socket=""

  # ── GPG: prepare keys for agent forwarding ──
  if command -v gpgconf >/dev/null 2>&1 && command -v gpg >/dev/null 2>&1; then
    gpg_local_socket=$(gpgconf --list-dirs agent-extra-socket 2>/dev/null) || true
    if [[ -n "$gpg_local_socket" ]]; then
      gpgconf --launch gpg-agent 2>/dev/null
      local pubkeys_b64 ownertrust_b64
      pubkeys_b64=$(gpg --armor --export 2>/dev/null | base64 | tr -d '\n') || true
      ownertrust_b64=$(gpg --export-ownertrust 2>/dev/null | base64 | tr -d '\n') || true
      if [[ -n "$pubkeys_b64" ]]; then
        echo "🔑 Forwarding GPG agent…" >&2
        script+='(
gpg_socket=$(gpgconf --list-dirs agent-socket 2>/dev/null) || exit 0
gpgconf --kill gpg-agent 2>/dev/null || true
[ -S "$gpg_socket" ] && rm -f "$gpg_socket"
sleep 1
'
        script+="printf '%s' '${pubkeys_b64}' | base64 -d | gpg --batch --import 2>/dev/null || true
printf '%s' '${ownertrust_b64}' | base64 -d | gpg --batch --import-ownertrust 2>/dev/null || true
"
        script+='gpgconf --kill gpg-agent 2>/dev/null || true
[ -S "$gpg_socket" ] && rm -f "$gpg_socket"
echo "GPG_SOCKET:${gpg_socket}"
)
'
      fi
    fi
  fi

  # ── Terminfo: install xterm-ghostty ──
  if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
    local infocmp="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/ncurses/bin/infocmp"
    if [[ -x "$infocmp" ]]; then
      local terminfo_b64
      terminfo_b64=$("$infocmp" -x xterm-ghostty 2>/dev/null | base64 | tr -d '\n') || true
      if [[ -n "$terminfo_b64" ]]; then
        echo "🖥️  Installing xterm-ghostty terminfo…" >&2
        script+="(printf '%s' '${terminfo_b64}' | base64 -d | tic -x - 2>/dev/null && echo 'TERMINFO_OK:1' || echo 'TERMINFO_OK:0')
"
      fi
    fi
  fi

  [[ -n "$script" ]] || return 0

  # Execute single preflight SSH
  local output
  output=$(printf '%s' "$script" | ssh -o ConnectTimeout=10 "$host" /bin/sh 2>/dev/null) || return 0

  # Parse labeled output
  local line
  while IFS= read -r line; do
    case "$line" in
      GPG_SOCKET:*)
        local remote_socket="${line#GPG_SOCKET:}"
        if [[ -n "$remote_socket" && -n "$gpg_local_socket" ]]; then
          _gpg_ssh_opts=(-o StreamLocalBindUnlink=yes -R "${remote_socket}:${gpg_local_socket}")
        fi
        ;;
      TERMINFO_OK:1)
        _term_env="TERM=xterm-ghostty"
        ;;
    esac
  done <<< "$output"
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

  _coder_preflight "$host"

  case "$mode" in
    ssh)
      local cmd=""
      [[ -n "$folder" ]] && cmd+="cd ${folder} && "
      [[ -n "$_term_env" ]] && cmd+="$_term_env "
      cmd+="/usr/bin/zsh -l"
      exec ssh -t "${_gpg_ssh_opts[@]}" "$host" "$cmd"
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
      local cmd=""
      [[ -n "$folder" ]] && cmd+="cd ${folder} && "
      [[ -n "$_term_env" ]] && cmd+="$_term_env "
      cmd+="otter claude-code"
      exec ssh -t "${_gpg_ssh_opts[@]}" "$host" "$cmd"
      ;;

    ccyolo)
      local cmd=""
      [[ -n "$folder" ]] && cmd+="cd ${folder} && "
      [[ -n "$_term_env" ]] && cmd+="$_term_env "
      cmd+="otter claude-code --dangerously-skip-permissions --permission-mode bypassPermissions --model global.anthropic.claude-opus-4-6-v1"
      exec ssh -t "${_gpg_ssh_opts[@]}" "$host" "$cmd"
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

