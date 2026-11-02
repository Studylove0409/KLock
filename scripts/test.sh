#!/usr/bin/env bash
# 纯逻辑自检，不需要 Xcode。
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
OUT="$(mktemp -t dropclock-tests)"

swiftc -O -sdk "$SDK" -target arm64-apple-macos13.0 -swift-version 5 \
  Dropclock/Support/TimerTextFormatter.swift \
  Tests/main.swift \
  -o "$OUT"

"$OUT"
STATUS=$?
rm -f "$OUT"
exit $STATUS
