#|------------------------------------------------------------|#
#| Color functions
#|------------------------------------------------------------|#

function color_table() {
  for x in {0..8}; do for i in {30..37}; do for a in {40..47}; do echo -ne "\e[$x;$i;$a""m\\\e[$x;$i;$a""m\e[0;37;40m "; done; echo; done; done; echo ""
}

function color_printf() {
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

  supported_colors=$(tput colors 2>/dev/null)
  if [ "$supported_colors" -gt 8 ]; then
    printf "\\033[${color}m%b\\033[0m" "$1"
  else
    printf "%b" "$1"
  fi
}
