#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Normalize TMPDIR (strip trailing slash for consistent path construction)
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

# Read JSON input from stdin
input=$(cat)

# Extract data
MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

# Calculate context usage
TOTAL_INPUT=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
CURRENT_TOKENS=$((TOTAL_INPUT + CACHE_READ))
PERCENT=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))

# Format tokens (e.g., "45.2K" or "1.2M")
format_tokens() {
    local tokens=$1
    if [ "$tokens" -ge 1000000 ]; then
        echo "$((tokens / 1000000)).$((tokens % 1000000 / 100000))M"
    elif [ "$tokens" -ge 1000 ]; then
        echo "$((tokens / 1000)).$((tokens % 1000 / 100))K"
    else
        echo "${tokens}"
    fi
}

TOKENS_FORMATTED=$(format_tokens "$CURRENT_TOKENS")
CONTEXT_SIZE_FORMATTED=$(format_tokens "$CONTEXT_SIZE")

# Create progress bar
create_progress_bar() {
    local percent=$1
    local width=10
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "["
    for ((i=0; i<filled; i++)); do printf "■"; done
    for ((i=0; i<empty; i++)); do printf "·"; done
    printf "]"
}

PROGRESS=$(create_progress_bar "$PERCENT")

# Get git branch
GIT_BRANCH=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    [ -n "$BRANCH" ] && GIT_BRANCH="$BRANCH"
fi

# Get project name (basename of project directory)
PROJECT_DIR=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // ""')
if [ -n "$PROJECT_DIR" ]; then
    PROJECT_NAME=$(basename "$PROJECT_DIR")
else
    PROJECT_NAME=""
fi

# Base ANSI color codes
BOLD_WHITE='\033[1;37m'
DIM_WHITE='\033[37m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
RESET='\033[0m'

# Usage-based color assignments
COLOR_MODEL="$BOLD_WHITE"
COLOR_TOKENS="$DIM_WHITE"
COLOR_BRANCH="$GREEN"
COLOR_PROJECT="$CYAN"

# Choose color based on percentage
if [ "$PERCENT" -lt 50 ]; then
    COLOR_PROGRESS="$DIM_WHITE"
elif [ "$PERCENT" -lt 80 ]; then
    COLOR_PROGRESS="$YELLOW"
else
    COLOR_PROGRESS="$RED"
fi

# Build statusline with colors
OUTPUT="${COLOR_MODEL}${MODEL}${RESET} | ${COLOR_PROGRESS}${PROGRESS} ${PERCENT}%${RESET} | ${COLOR_TOKENS}${TOKENS_FORMATTED}/${CONTEXT_SIZE_FORMATTED}${RESET}"

if [ -n "$PROJECT_NAME" ]; then
    OUTPUT="$OUTPUT | ${COLOR_PROJECT}${PROJECT_NAME}${RESET}"
    if [ -n "$GIT_BRANCH" ]; then
        OUTPUT="$OUTPUT ${COLOR_TOKENS}(${COLOR_BRANCH}${GIT_BRANCH}${COLOR_TOKENS})${RESET}"
    fi
elif [ -n "$GIT_BRANCH" ]; then
    OUTPUT="$OUTPUT | ${COLOR_BRANCH}${GIT_BRANCH}${RESET}"
fi

echo -e "$OUTPUT"
