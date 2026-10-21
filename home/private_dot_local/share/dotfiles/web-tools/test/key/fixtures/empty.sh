#!/bin/sh
# Test fixture: records the call, prints nothing, exits 0.
LOG_DIR="${WEBTOOLS_TEST_LOG_DIR:-$(dirname "$0")}"
echo "$#|$1|$2" >> "$LOG_DIR/calls.log"
