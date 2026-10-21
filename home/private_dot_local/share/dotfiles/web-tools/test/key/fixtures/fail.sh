#!/bin/sh
# Test fixture: records the call, prints a value, exits nonzero. The value must never surface.
LOG_DIR="${WEBTOOLS_TEST_LOG_DIR:-$(dirname "$0")}"
echo "$#|$1|$2" >> "$LOG_DIR/calls.log"
echo "leaky-value-must-not-surface"
exit 1
