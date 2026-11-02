#!/usr/bin/env bash
# 不依赖 Xcode 打包可运行的 .app（仅用 Command Line Tools）。
# 用法: bash scripts/build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Dropclock.app"
SDK="$(xcrun --show-sdk-path)"

echo "==> 编译"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -sdk "$SDK" -target arm64-apple-macos13.0 \
  -swift-version 5 \
  -o "$APP/Contents/MacOS/Dropclock" \
  $(find Dropclock -name "*.swift")

echo "==> 写入 Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>Dropclock</string>
	<key>CFBundleExecutable</key>
	<string>Dropclock</string>
	<key>CFBundleIdentifier</key>
	<string>com.Wrkx.Dropclock.local</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Dropclock</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.9.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSRemindersUsageDescription</key>
	<string>Dropclock 需要在「提醒事项」中创建和删除提醒，以便为你的计时器生成配套提醒。</string>
</dict>
</plist>
PLIST

echo "==> 拷贝音频资源"
cp Dropclock/Sounds/*.mp3 "$APP/Contents/Resources/"

echo "==> 临时签名"
# Desktop 属于 iCloud 同步目录，直接 codesign 会因扩展属性报 detritus 错误，
# 所以先在临时目录签名再拷回。
TMP="$(mktemp -d)"
ditto "$APP" "$TMP/Dropclock.app"
xattr -cr "$TMP/Dropclock.app"
codesign --force --sign - "$TMP/Dropclock.app"
rm -rf "$APP"
ditto "$TMP/Dropclock.app" "$APP"
rm -rf "$TMP"
codesign --verify "$APP"

echo "==> 完成: $APP"

if [[ "${1:-}" == "--run" ]]; then
  pkill -f "$APP" 2>/dev/null || true
  sleep 1
  open "$APP"
  echo "==> 已启动"
fi
