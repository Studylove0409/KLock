#!/usr/bin/env bash
# 在独立进程中验证偏好与权限状态，不需要 Xcode 或系统授权。
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path)"
OUT="$(mktemp -t dropclock-preferences-tests)"
CACHE="${CLANG_MODULE_CACHE_PATH:-/private/tmp/dropclock-module-cache}"
TEST_HOME="$(mktemp -d -t dropclock-preferences-home)"
mkdir -p "$TEST_HOME/Library/Preferences"

swiftc -parse-as-library -module-cache-path "$CACHE" -sdk "$SDK" \
  -target arm64-apple-macos13.0 -swift-version 5 \
  KLock/Preferences/PreferencesViewModel.swift \
  Tests/Preferences/main.swift \
  -o "$OUT"

CFFIXED_USER_HOME="$TEST_HOME" "$OUT"
rm -f "$OUT"
