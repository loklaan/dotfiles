---
name: lochy:coding:shell
description: Guidelines and patterns for writing bash/shell scripts. Use when creating new shell scripts, bin scripts, or bash utilities. Includes script templates, header comments, error handling, and common patterns.
---

# Coding Shell Scripts

## Overview

This skill provides templates and patterns for writing bash scripts. Choose the appropriate template based on your needs:

- **Simple Script Structure**: For straightforward utilities and single-purpose tools
- **Full Script Template**: For complex scripts needing logging, cleanup handlers, and robust error handling

## Simple Script Structure

For straightforward scripts (utilities, single-purpose tools):

```bash
#!/usr/bin/env bash

main() {
  # Script logic here
  local arg="$1"

  if [ -z "$arg" ]; then
    echo "Usage: $(basename "$0") <argument>" >&2
    exit 1
  fi

  # Do the work
  echo "Processing: $arg"
}

main "$@"
```

**Important:** Standalone scripts MUST use `exit` (not `return`) for error codes, since they run in their own process.

## Full Script Template

For more complex scripts with logging, cleanup, and robust error handling:

```shell
#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Normalize TMPDIR (strip trailing slash for consistent path construction)
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#/ Usage:
#/ Description:
#/ Examples:
#/ Options:
#/   --help: Display this help message
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }
expr "$*" : ".*--help" > /dev/null && usage

readonly LOG_FILE="${TMPDIR}/$(basename "$0").log"
_print() {
  case "$1" in
    black) color="30" ;; red) color="31" ;; green) color="32" ;;
    yellow) color="33" ;; blue) color="34" ;; magenta) color="35" ;;
    cyan) color="36" ;; white) color="37" ;;
    *) echo "Unknown color: $1" >&2; return 1 ;;
  esac
  shift
  while [ "$#" -gt 1 ]; do
    case "$1" in
      bold) color="${color};1" ;; dim) color="${color};2" ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
    shift
  done
  supported_colors=$(tput colors 2>/dev/null || echo 0)
  if [ -n "$supported_colors" ] && [ "$supported_colors" -gt 8 ]; then
    printf "\\033[${color}m%b\\033[0m\\n" "$1"
  else
    printf "%b\n" "$1"
  fi
}
info()    { _print cyan "info $@" | tee -a "$LOG_FILE" >&2 ; }
warning() { _print yellow "warning $@" | tee -a "$LOG_FILE" >&2 ; }
error()   { _print red "error $@" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { _print red bold "fatal $@" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

cleanup() {
  # Remove temporary files
  # Restart services
  # ...
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  trap cleanup EXIT
  # Script goes here
  # ...
fi
```

## Script Validation

**CRITICAL: Always validate shell scripts after creating or editing them.**

### Required Validation Steps

After creating or editing any shell script, you MUST run both validation tools:

1. **Syntax Check with bash -n**
   ```shell
   bash -n script.sh
   ```

   Catches basic syntax errors:
   - Missing closing quotes
   - Unmatched brackets or braces
   - Invalid command syntax

2. **Static Analysis with shellcheck**
   ```shell
   shellcheck script.sh
   ```

   Catches deeper issues:
   - Quoting problems (word splitting, glob expansion)
   - Deprecated or unsafe syntax
   - Common bugs and anti-patterns
   - Unused or misspelled variables
   - Portability issues

### Validation Pattern

Run both checks together:

```shell
bash -n script.sh && shellcheck script.sh
```

Only consider the script complete after both tools pass without errors.

### Handling Shellcheck Warnings

When shellcheck warnings are intentional, disable them with directives:

```shell
# Disable specific warning for one line
# shellcheck disable=SC2086
echo $unquoted_on_purpose

# Disable multiple codes for entire file (at top)
# shellcheck disable=SC2086,SC2181

# Document why you're disabling
# We want word splitting here for argument passing
# shellcheck disable=SC2086
command $args
```

**Common codes you might need to disable:**
- `SC2086`: Word splitting/globbing (when intentional for argument passing)
- `SC2181`: Testing `$?` explicitly (when needed for clarity)
- `SC1090`: Dynamic source paths (shellcheck can't follow them)
- `SC2034`: Unused variables (e.g., when reading into multiple vars)

**Important:** Only disable shellcheck warnings when you understand why they're triggered and have a valid reason to ignore them. Document your reasoning in comments.

## Bash Constructs

For loops, case statements, ternary expressions, file/stdin patterns, and other common constructs, see [references/constructs.md](references/constructs.md).

