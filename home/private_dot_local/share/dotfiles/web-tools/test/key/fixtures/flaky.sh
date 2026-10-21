#!/bin/sh
# Test fixture: the first three invocations print nothing; later ones print a key.
LOG_DIR="${WEBTOOLS_TEST_LOG_DIR:-$(dirname "$0")}"
echo "$#|$1|$2" >> "$LOG_DIR/calls.log"
N=$(wc -l < "$LOG_DIR/calls.log" | tr -d ' ')
if [ "$N" -le 3 ]; then exit 0; fi
echo "exa-test-key-after-retry"
