---
name: coding-shell-scripts
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
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#/ Usage:
#/ Description:
#/ Examples:
#/ Options:
#/   --help: Display this help message
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }
expr "$*" : ".*--help" > /dev/null && usage

readonly LOG_FILE="/tmp/$(basename "$0").log"
info()    { echo "[INFO]    $@" | tee -a "$LOG_FILE" >&2 ; }
warning() { echo "[WARNING] $@" | tee -a "$LOG_FILE" >&2 ; }
error()   { echo "[ERROR]   $@" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { echo "[FATAL]   $@" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

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

## Bash Constructs

**`for`**
```shell
for i in ( ls some-directory ); do
  echo $i
done

SomeArray=("foo"  "bar"  "baz")
for item in ${SomeArray[*]}; do
  echo $item
done
```

**`case`**
```shell
case "$variable" in
  abc)  echo "\$variable = abc" ;;
  xyz)  echo "\$variable = xyz" ;;
esac
```

**`ln`**
```shell
ln -s <real_file> <future_link>
```

**`select`**
```shell
select result in Yes No Cancel
do
  echo $result
done
```

**`tput`**
```shell
tput cuu1 # Move cursor up by one line
tput el   # Clear the line
```

## Common Patterns

**Ternary expressions**

```shell
<expression> && <on-true expression> || <on-false expression>
# See below example for file/stdin to variable.
```

**File or stdin assignment**

Assign either a file or stdin (piped input) to a variable, with fallbacks:

```shell
# Use a filepath from args when available, or use stdin
[ $# -ge 1 -a -f "$1" ] && input="$1" || input="-"
content=$(cat $input)

# Use stdin if pipe is occupied, otherwise use a file
(test -s /dev/stdin) && input="-" || input="./config.json"
content=(cat $input)
```

## Arithmetic Operations

Use `(())` for arithmetic:

```shell
echo $(( 5 - 1 ))
```

## CLI Arguments

More involved: https://medium.com/@Drew_Stokes/bash-argument-parsing-54f3b81a6a8f

```shell
# Simple double dash arg
arg_no_bump="false"
expr "$*" : ".*--no-bump" > /dev/null && arg_no_bump="true"
```

## Reference Links

http://tldp.org/LDP/abs/html/index.html  
https://stackoverflow.com/documentation/bash/topics  
https://dev.to/thiht/shell-scripts-matter  

