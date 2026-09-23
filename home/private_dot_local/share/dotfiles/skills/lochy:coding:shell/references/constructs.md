# Bash Constructs Cheat Sheet

Personal quick-reference for common bash patterns.

## Loops

**`for`**
```shell
for i in some-directory/*; do
  echo "$i"
done

some_array=("foo" "bar" "baz")
for item in "${some_array[@]}"; do
  echo "$item"
done
```

## Control Flow

**`case`**
```shell
case "$variable" in
  abc)  echo "\$variable = abc" ;;
  xyz)  echo "\$variable = xyz" ;;
esac
```

**`select`**
```shell
select result in Yes No Cancel; do
  echo "$result"
  break
done
```

## Common Commands

**`ln`** (symlinks)
```shell
ln -s <real_file> <future_link>
```

**`tput`** (terminal control)
```shell
tput cuu1 # Move cursor up by one line
tput el   # Clear the line
```

## Arithmetic

Use `(())` for arithmetic:
```shell
echo $(( 5 - 1 ))
```

## Ternary Expressions

```shell
<expression> && <on-true> || <on-false>
```

## File or Stdin Assignment

Assign either a file or stdin (piped input) to a variable:

```shell
# Use a filepath from args when available, or use stdin
[ $# -ge 1 ] && [ -f "$1" ] && input="$1" || input="-"
content=$(cat "$input")

# Use stdin if pipe is occupied, otherwise use a file
(test -s /dev/stdin) && input="-" || input="./config.json"
content=$(cat "$input")
```

## CLI Arguments

```shell
# Simple double dash arg
arg_no_bump="false"
expr "$*" : ".*--no-bump" > /dev/null && arg_no_bump="true"
```

More involved argument parsing: https://medium.com/@Drew_Stokes/bash-argument-parsing-54f3b81a6a8f
