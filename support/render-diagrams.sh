#!/usr/bin/env bash
set -euo pipefail

#/ Usage:
#/   render-diagrams.sh [--check]
#/
#/ Description:
#/   Render D2 diagram sources in support/ to dark and light SVGs.
#/   With --check, render to temp files and diff against committed SVGs
#/   (exit 1 if stale). Without --check, overwrite SVGs in place.
#/
#/ Options:
#/   --check:  Compare only, don't overwrite (for CI / check-refs)
#/   --help:   Display this help message
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }
expr "$*" : ".*--help" > /dev/null && usage

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

CHECK_MODE=false
expr "$*" : ".*--check" > /dev/null && CHECK_MODE=true

LAYOUT="elk"
DARK_THEME="200"
LIGHT_THEME="0"

# Each D2 source in support/ gets a dark and light SVG
sources=("$DIR"/*.d2)

if [ ${#sources[@]} -eq 0 ]; then
  echo "No .d2 files found in $DIR" >&2
  exit 1
fi

stale=0

for source in "${sources[@]}"; do
  base="$(basename "$source" .d2)"

  dark_out="$DIR/${base}-dark.svg"
  light_out="$DIR/${base}-light.svg"

  if [ "$CHECK_MODE" = true ]; then
    dark_tmp="$TMPDIR/${base}-dark.svg"
    light_tmp="$TMPDIR/${base}-light.svg"

    mise exec -- d2 --theme "$DARK_THEME" --layout "$LAYOUT" "$source" "$dark_tmp" 2>/dev/null
    mise exec -- d2 --theme "$LIGHT_THEME" --layout "$LAYOUT" "$source" "$light_tmp" 2>/dev/null

    # Strip the d2- class ID prefix (contains a hash that changes between renders)
    normalize() { sed 's/d2-[0-9]*/d2-HASH/g' "$1"; }

    if ! diff -q <(normalize "$dark_tmp") <(normalize "$dark_out") >/dev/null 2>&1; then
      echo "STALE: $dark_out" >&2
      stale=1
    fi
    if ! diff -q <(normalize "$light_tmp") <(normalize "$light_out") >/dev/null 2>&1; then
      echo "STALE: $light_out" >&2
      stale=1
    fi

    rm -f "$dark_tmp" "$light_tmp"
  else
    echo "Rendering $base..."
    mise exec -- d2 --theme "$DARK_THEME" --layout "$LAYOUT" "$source" "$dark_out"
    mise exec -- d2 --theme "$LIGHT_THEME" --layout "$LAYOUT" "$source" "$light_out"
  fi
done

if [ "$CHECK_MODE" = true ]; then
  if [ "$stale" -eq 1 ]; then
    echo "Run 'support/render-diagrams.sh' to update." >&2
    exit 1
  else
    echo "All SVGs are fresh."
  fi
fi
