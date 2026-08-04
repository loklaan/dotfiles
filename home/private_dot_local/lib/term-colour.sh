#!/usr/bin/env bash

#|----------------------------------------------------------------------------|
#| Terminal Colour Primitives                                                 |
#|                                                                            |
#| ANSI colour output, degrading to plain text when the terminal cannot        |
#| render colour. Deliberately tiny and free of any logging machinery.         |
#|                                                                            |
#| Usage:                                                                     |
#|   source "${HOME}/.local/lib/term-colour.sh"                              |
#|   color_printf magenta "text"                                              |
#|   color_printf red bold "text\n"                                           |
#|                                                                            |
#| WHY this is separate from bash-logging.sh:                                  |
#|   Interactive zsh (via .zshrc -> term.zsh, and the starship plugin) needs   |
#|   colour and nothing else. Sourcing bash-logging.sh for it defined info,    |
#|   warning, error, fatal and run_quiet as shell functions in every           |
#|   interactive shell — `info` shadowing GNU info being the worst of it.      |
#|   Keep colour here, keep logging there, and the shell namespace stays       |
#|   clean.                                                                    |
#|                                                                            |
#| Safe to source more than once, and safe under `set -u`.                     |
#|----------------------------------------------------------------------------|

color_printf() {
  local color
  case "$1" in
    black) color="30" ;;
    red) color="31" ;;
    green) color="32" ;;
    yellow) color="33" ;;
    blue) color="34" ;;
    magenta) color="35" ;;
    cyan) color="36" ;;
    white) color="37" ;;
    *) echo "Unknown color: $1" >&2; return 1 ;;
  esac

  shift
  while [ "$#" -gt 1 ]; do
    case "$1" in
      bold) color="${color};1" ;;
      italic) color="${color};3" ;;
      underline) color="${color};4" ;;
      dim) color="${color};2" ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
    shift
  done

  local supported_colors
  supported_colors=$(tput colors 2>/dev/null || echo 0)
  if [ -n "$supported_colors" ] && [ "$supported_colors" -gt 8 ]; then
    printf "\\033[${color}m%b\\033[0m" "$1"
  else
    printf "%b" "$1"
  fi
}

# Same, with a trailing newline.
color_print() {
  color_printf "$@"
  printf "\n"
}
