#!/usr/bin/env bash
# Runs a command; if it fails, publishes the relevant part of its output as
# an error annotation, which is visible on GitHub without signing in.
set -o pipefail
"$@" 2>&1 | tee run.log && exit 0
status=$?
msg=$(grep -E -A25 "What went wrong|error •|warning •|\[E\]|Expected:|Error:|error:|FAILURE|Exception" run.log | head -120)
[ -z "$msg" ] && msg=$(tail -60 run.log)
msg=${msg//'%'/%25}; msg=${msg//$'\r'/%0D}; msg=${msg//$'\n'/%0A}
echo "::error title=$* failed::$msg"
exit $status
