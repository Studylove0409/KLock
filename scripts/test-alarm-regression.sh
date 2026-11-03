#!/usr/bin/env bash
# 真实的计时器及声音管理逻辑，使用无窗口的提醒卡片测试替身。
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
OUT="$(mktemp -t dropclock-alarm-tests)"
CACHE="${CLANG_MODULE_CACHE_PATH:-/private/tmp/dropclock-module-cache}"
SOURCES=()
while IFS= read -r -d '' file; do
  if [[ "$file" != "KLock/Panels/ReminderAlertPanel.swift" ]]; then
    SOURCES+=("$file")
  fi
done < <(find KLock -name '*.swift' -print0)

swiftc -DDROPCLOCK_TESTING -Xfrontend -disable-access-control \
  -module-cache-path "$CACHE" -sdk "$SDK" \
  -target arm64-apple-macos13.0 -swift-version 5 \
  "${SOURCES[@]}" Tests/AlarmRegression/ReminderAlertPanel.swift \
  Tests/AlarmRegression/main.swift -o "$OUT"

if OUTPUT="$("$OUT")"; then
  printf '%s\n' "$OUTPUT"
else
  STATUS=$?
  printf '%s\n' "$OUTPUT"
  exit "$STATUS"
fi
if [[ "$OUTPUT" != *"声音回归测试全部通过"* ]]; then
  printf '%s\n' "声音回归测试进程未执行完全部断言" >&2
  exit 1
fi
rm -f "$OUT"
