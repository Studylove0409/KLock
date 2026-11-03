#!/usr/bin/env bash
# 不依赖 Xcode 打包可运行的 .app（仅用 Command Line Tools）。
# 用法: bash scripts/build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Dropclock.app"
SDK="$(xcrun --show-sdk-path)"
CACHE="${CLANG_MODULE_CACHE_PATH:-/private/tmp/dropclock-module-cache}"

echo "==> 编译"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -module-cache-path "$CACHE" -sdk "$SDK" -target arm64-apple-macos13.0 \
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
	<string>KLock</string>
	<key>CFBundleExecutable</key>
	<string>Dropclock</string>
	<key>CFBundleIdentifier</key>
	<string>com.Wrkx.Dropclock.local</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>KLock</string>
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
	<string>KLock 需要在「提醒事项」中创建和删除提醒，以便为你的计时器生成配套提醒。</string>
</dict>
</plist>
PLIST

echo "==> 拷贝音频资源"
cp Dropclock/Sounds/*.mp3 "$APP/Contents/Resources/"

echo "==> 拷贝图标"
if [[ -f assets/AppIcon.icns ]]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
for status_icon in assets/StatusItemTemplate.png assets/StatusItemTemplate@2x.png; do
  if [[ -f "$status_icon" ]]; then
    cp "$status_icon" "$APP/Contents/Resources/"
  fi
done
if [[ -f assets/StatusItemTemplate@2x.png ]]; then
  cp assets/StatusItemTemplate@2x.png "$APP/Contents/Resources/StatusItemTemplate@2x.png"
fi

echo "==> 临时签名"
# Desktop 属于 iCloud 同步目录；在本地副本签名并严格验证，再用 ditto 覆盖回写。
# 保留验签副本，整个构建过程无需递归删除已有应用目录。
VERIFIED_APP="/private/tmp/Dropclock-DeskMinder-Verified.app"
ditto "$APP" "$VERIFIED_APP"
xattr -cr "$VERIFIED_APP"
codesign --force --sign - "$VERIFIED_APP"
codesign --verify --deep --strict "$VERIFIED_APP"
ditto "$VERIFIED_APP" "$APP"
codesign --verify "$APP"

echo "==> 完成: $APP"

RUN=false
INSTALL=false
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --run) RUN=true ;;
    --install) INSTALL=true ;;
    --force) FORCE=true ;;
  esac
done

if $RUN; then
  pkill -f "$APP" 2>/dev/null || true
  sleep 1
  open "$APP"
  echo "==> 已启动"
fi

if $INSTALL; then
  TARGET="/Applications/Dropclock.app"
  if [[ -d "$TARGET" ]] && ! $FORCE; then
    echo "!! $TARGET 已存在，未覆盖。确认替换请追加 --force"
  else
    rm -rf "$TARGET"
    ditto "$APP" "$TARGET"
    echo "==> 已安装到 $TARGET"
  fi
fi

