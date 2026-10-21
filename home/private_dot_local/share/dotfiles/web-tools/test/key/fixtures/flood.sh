#!/bin/sh
# Test fixture: writes 8 MiB to stdout to exercise the stdout cap.
LOG_DIR="${WEBTOOLS_TEST_LOG_DIR:-$(dirname "$0")}"
echo "$#|$1|$2" >> "$LOG_DIR/calls.log"
head -c 8388608 /dev/zero | tr '\0' 'x'
