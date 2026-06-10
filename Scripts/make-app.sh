#!/usr/bin/env bash
# 把 SwiftPM 可执行 CmuxApp 打包成 cmux.app（带 bundle id），让原生通知 + 点击跳转可用。
# 用法：Scripts/make-app.sh [debug|release]，默认 release。产物在仓库根目录 cmux.app。
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build -c $CONFIG --product CmuxApp"
swift build -c "$CONFIG" --product CmuxApp

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/cmux.app"
BUNDLE_ID="com.cmux.app"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/CmuxApp" "$APP/Contents/MacOS/CmuxApp"

# SwiftPM 资源 bundle（logo 等）放到 Resources/，Bundle.module 会在 main bundle 资源路径里找到，
# 且不会像放在 MacOS/ 那样破坏 codesign。
if [ -d "$BIN_DIR/Cmux_CmuxApp.bundle" ]; then
  cp -R "$BIN_DIR/Cmux_CmuxApp.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CmuxApp</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>cmux</string>
  <key>CFBundleDisplayName</key>
  <string>cmux</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# ad-hoc 签名：通知授权 / 持久化权限提示需要稳定的代码签名标识。
echo "==> ad-hoc 代码签名"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "   (codesign 失败，可忽略；通知可能需要手动授权)"

echo "==> 完成：$APP"
echo "    运行：open $APP   （或双击）"
