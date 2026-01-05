#!/usr/bin/env bash

#|-----------------------------------------------------------------------------|
#| Cross-platform file agnostic open                                          |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Provides the open_command function for opening files/URLs with the         |
#| appropriate system command across different platforms (macOS, Linux,       |
#| Windows/WSL, Cygwin).                                                       |
#|                                                                             |
#|-----------------------------------------------------------------------------|

open_command() {
  local open_cmd
  local file_arg="$1"

  # define the open command
  case "$OSTYPE" in
    darwin*)  open_cmd='open' ;;
    cygwin*)  open_cmd='cygstart' ;;
    linux*)   ! [[ $(uname -a) =~ "Microsoft" ]] && open_cmd='xdg-open' || {
                open_cmd='cmd.exe /c start ""'
                [[ -e "$file_arg" ]] && { file_arg="$(wslpath -w "$(realpath "$file_arg")")" || return 1; }
              } ;;
    msys*)    open_cmd='start ""' ;;
    *)        echo "Platform $OSTYPE not supported"
              return 1
              ;;
  esac

  # don't use nohup on OSX
  if [[ "$OSTYPE" == darwin* ]]; then
    $open_cmd "$file_arg" &>/dev/null
  else
    nohup $open_cmd "$file_arg" &>/dev/null
  fi
}