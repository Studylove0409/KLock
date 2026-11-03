#!/usr/bin/env bash
# 纯逻辑自检，不需要 Xcode。
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
OUT="$(mktemp -t dropclock-tests)"
CACHE="${CLANG_MODULE_CACHE_PATH:-/private/tmp/dropclock-module-cache}"

swiftc -O -module-cache-path "$CACHE" -sdk "$SDK" -target arm64-apple-macos13.0 -swift-version 5 \
  KLock/Support/TimerTextFormatter.swift \
  KLock/Model/HistoryStore.swift \
  KLock/Model/SavedTimers.swift \
  KLock/Model/TimerMath.swift \
  Tests/main.swift \
  -o "$OUT"

"$OUT"
STATUS=$?
rm -f "$OUT"
exit $STATUS
