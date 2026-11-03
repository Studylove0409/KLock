#!/usr/bin/env bash
# 编译完整应用源码并运行计时器回归测试。
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
OUT="$(mktemp -t dropclock-regression-tests)"
CACHE="${CLANG_MODULE_CACHE_PATH:-/private/tmp/dropclock-module-cache}"
SOURCES=()
while IFS= read -r -d '' file; do
  SOURCES+=("$file")
done < <(find Dropclock -name '*.swift' -print0)

swiftc -DDROPCLOCK_TESTING -module-cache-path "$CACHE" -sdk "$SDK" \
  -target arm64-apple-macos13.0 -swift-version 5 \
  "${SOURCES[@]}" Tests/Regression/main.swift \
  -o "$OUT"

if OUTPUT="$("$OUT")"; then
  printf '%s\n' "$OUTPUT"
else
  STATUS=$?
  printf '%s\n' "$OUTPUT"
  exit "$STATUS"
fi
if [[ "$OUTPUT" != *"回归测试全部通过"* ]]; then
  printf '%s\n' "回归测试进程未执行完全部断言" >&2
  exit 1
fi
rm -f "$OUT"

bash scripts/test-alarm-regression.sh
