#!/usr/bin/env bash
# Warns (with the resolved file attached) when pubspec.lock is missing from
# git or out of date, so it can be committed without a local Flutter install.
if git ls-files --error-unmatch pubspec.lock >/dev/null 2>&1 && git diff --quiet -- pubspec.lock; then
  exit 0
fi
lock=$(cat pubspec.lock)
lock=${lock//'%'/%25}; lock=${lock//$'\r'/%0D}; lock=${lock//$'\n'/%0A}
echo "::warning title=pubspec.lock is missing or out of date - commit this version::$lock"
