#!/usr/bin/env bash
# 把 SwiftPM 可执行 ConductorApp 打包成 Conductor.app（带 bundle id），让原生通知 + 点击跳转可用。
# 用法：Scripts/make-app.sh [debug|release]，默认 release。产物在仓库根目录 Conductor.app。
set -euo pipefail

CONFIG="${1:-release}"
VERSION="${VERSION:-0.0.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build -c $CONFIG --product ConductorApp"
swift build -c "$CONFIG" --product ConductorApp

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/Conductor.app"
BUNDLE_ID="com.conductor.app"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/ConductorApp" "$APP/Contents/MacOS/ConductorApp"

# SwiftPM 资源 bundle（logo、本地化文案等）放到 Resources/，Bundle.module 会在 main bundle
# 资源路径里找到，且不会像放在 MacOS/ 那样破坏 codesign。
# 注意：每个带资源的 target 都有自己的 bundle（ConductorApp / ConductorCore），缺一个就会在
# Bundle.module 访问时 fatalError。
for bundle in "$BIN_DIR"/Conductor_*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# 应用图标
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>ConductorApp</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>Conductor</string>
  <key>CFBundleDisplayName</key>
  <string>Conductor</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
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
