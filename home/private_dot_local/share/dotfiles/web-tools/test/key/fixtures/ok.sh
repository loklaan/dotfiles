#!/bin/sh
# Test fixture: records its argv (count|arg1|arg2) and prints a fake key. Never real BWS.
LOG_DIR="${WEBTOOLS_TEST_LOG_DIR:-$(dirname "$0")}"
echo "$#|$1|$2" >> "$LOG_DIR/calls.log"
echo "exa-test-key-value"
