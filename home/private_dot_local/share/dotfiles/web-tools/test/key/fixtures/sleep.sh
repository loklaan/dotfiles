#!/bin/sh
# Test fixture: records its pid and a background grandchild pid, then waits.
LOG_DIR="${WEBTOOLS_TEST_LOG_DIR:-$(dirname "$0")}"
# The test reads the pid files to check that interruption kills both.
echo "$#|$1|$2" >> "$LOG_DIR/calls.log"
echo "$$" > "$LOG_DIR/sleep.pid"
sleep 30 &
echo "$!" > "$LOG_DIR/sleep.grand"
wait
