#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

./Scripts/prepare-ghosttykit.sh
CONFIGURATION="${CONDUCTOR_BUILD_CONFIGURATION:-release}"
case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "Unsupported CONDUCTOR_BUILD_CONFIGURATION: $CONFIGURATION" >&2
    echo "Use 'debug' or 'release'." >&2
    exit 2
    ;;
esac
SWIFT_BUILD_ARGS=(-c "$CONFIGURATION")
if [[ "$CONFIGURATION" == "release" && "${CONDUCTOR_CROSS_MODULE_OPTIMIZATION:-1}" != "0" ]]; then
  SWIFT_BUILD_ARGS+=(-Xswiftc -cross-module-optimization)
fi
swift build "${SWIFT_BUILD_ARGS[@]}"
BIN_PATH="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"

APP="$ROOT/.build/Conductor.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH/Conductor" "$MACOS/Conductor"
swift "$ROOT/Scripts/generate-app-icon.swift" "$RESOURCES/AppIcon.icns"

copy_ghostty_resources() {
  local ghostty_root=""
  if [[ -d "$ROOT/Resources/ghostty/shell-integration" ]]; then
    ghostty_root="$ROOT/Resources/ghostty"
  elif [[ -d "/Applications/Ghostty.app/Contents/Resources/ghostty/shell-integration" ]]; then
    ghostty_root="/Applications/Ghostty.app/Contents/Resources/ghostty"
  fi

  if [[ -z "$ghostty_root" ]]; then
    echo "warning: Ghostty resources not found; bundled shell integration will rely on runtime fallbacks" >&2
    return
  fi

  mkdir -p "$RESOURCES/ghostty"
  rsync -a --delete "$ghostty_root/" "$RESOURCES/ghostty/"

  local ghostty_parent
  ghostty_parent="$(dirname "$ghostty_root")"
  if [[ -d "$ghostty_parent/terminfo" ]]; then
    mkdir -p "$RESOURCES/terminfo"
    rsync -a --delete "$ghostty_parent/terminfo/" "$RESOURCES/terminfo/"
  elif [[ -d "$ghostty_root/terminfo" ]]; then
    mkdir -p "$RESOURCES/terminfo"
    rsync -a --delete "$ghostty_root/terminfo/" "$RESOURCES/terminfo/"
  fi
}

copy_ghostty_resources

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Conductor</string>
  <key>CFBundleIdentifier</key>
  <string>app.conductor.dev</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Conductor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeDescription</key>
      <string>Conductor Terminal Tab</string>
      <key>UTTypeIdentifier</key>
      <string>app.conductor.terminal-tab</string>
      <key>UTTypeTagSpecification</key>
      <dict/>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP"
