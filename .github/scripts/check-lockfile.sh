#!/usr/bin/env bash
# Warns when pubspec.lock is missing from git or out of date, attaching the
# resolved file so it can be committed without a local Flutter install.
# Annotations are capped at 4 KB, so the file is gzipped, base64-encoded and
# split into numbered parts. To restore: join the parts, then
#   base64 -d | gunzip > pubspec.lock
if git ls-files --error-unmatch pubspec.lock >/dev/null 2>&1 && git diff --quiet -- pubspec.lock; then
  exit 0
fi
encoded=$(gzip -9c pubspec.lock | base64 | tr -d '\n')
total=$(( (${#encoded} + 3499) / 3500 ))
for (( i = 0; i < total; i++ )); do
  echo "::warning title=pubspec.lock is missing or out of date (gzip+base64 part $((i + 1))/$total)::${encoded:i*3500:3500}"
done
