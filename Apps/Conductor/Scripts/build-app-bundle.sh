#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

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
DEFAULT_MARKETING_VERSION="0.1.0"
if [[ -f "$ROOT/VERSION" ]]; then
  DEFAULT_MARKETING_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
fi
BUNDLE_IDENTIFIER="${CONDUCTOR_BUNDLE_IDENTIFIER:-app.conductor.dev}"
BUNDLE_DISPLAY_NAME="${CONDUCTOR_BUNDLE_DISPLAY_NAME:-Conductor}"
MARKETING_VERSION="${CONDUCTOR_MARKETING_VERSION:-$DEFAULT_MARKETING_VERSION}"
BUILD_NUMBER="${CONDUCTOR_BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="${CONDUCTOR_MIN_SYSTEM_VERSION:-14.0}"
APP_CATEGORY="${CONDUCTOR_APP_CATEGORY:-public.app-category.developer-tools}"
UPDATE_MANIFEST_URL="${CONDUCTOR_UPDATE_MANIFEST_URL:-https://github.com/zhengzizhe/conductor/releases/latest/download/latest-stable-macos-arm64.json}"

APP="$ROOT/.build/Conductor.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
EXECUTABLE="$MACOS/Conductor"
PRODUCT_EXECUTABLE=""
PRODUCT_BIN_DIR=""

prepare_dependencies() {
  ./Scripts/prepare-ghosttykit.sh
}

build_product() {
  swift build "${SWIFT_BUILD_ARGS[@]}"
  local bin_path
  bin_path="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
  PRODUCT_BIN_DIR="$bin_path"
  PRODUCT_EXECUTABLE="$bin_path/Conductor"

  if [[ ! -x "$PRODUCT_EXECUTABLE" ]]; then
    echo "Built Conductor executable not found at $PRODUCT_EXECUTABLE" >&2
    exit 1
  fi
}

copy_swiftpm_resources() {
  shopt -s nullglob
  local resource_bundles=("$PRODUCT_BIN_DIR"/*.bundle)
  shopt -u nullglob
  if [[ ${#resource_bundles[@]} -eq 0 ]]; then
    echo "warning: SwiftPM resource bundles not found in $PRODUCT_BIN_DIR" >&2
    return
  fi

  local resource_bundle
  for resource_bundle in "${resource_bundles[@]}"; do
    local bundle_name
    bundle_name="$(basename "$resource_bundle")"
    rm -rf "$RESOURCES/$bundle_name"
    cp -R "$resource_bundle" "$RESOURCES/$bundle_name"
  done
}

create_app_layout() {
  rm -rf "$APP"
  mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"
  cp "$PRODUCT_EXECUTABLE" "$EXECUTABLE"
  swift "$ROOT/Scripts/generate-app-icon.swift" "$RESOURCES/AppIcon.icns"
}

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

write_info_plist() {
  cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$(xml_escape "$BUNDLE_DISPLAY_NAME")</string>
  <key>CFBundleExecutable</key>
  <string>Conductor</string>
  <key>CFBundleIdentifier</key>
  <string>$(xml_escape "$BUNDLE_IDENTIFIER")</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(xml_escape "$BUNDLE_DISPLAY_NAME")</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(xml_escape "$MARKETING_VERSION")</string>
  <key>CFBundleVersion</key>
  <string>$(xml_escape "$BUILD_NUMBER")</string>
  <key>LSApplicationCategoryType</key>
  <string>$(xml_escape "$APP_CATEGORY")</string>
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
  <string>$(xml_escape "$MIN_SYSTEM_VERSION")</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Conductor. All rights reserved.</string>
  <key>ConductorUpdateManifestURL</key>
  <string>$(xml_escape "$UPDATE_MANIFEST_URL")</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$CONTENTS/Info.plist" >/dev/null
  fi
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

sign_app_bundle() {
  if command -v codesign >/dev/null 2>&1; then
    local identity
    identity="$(resolve_signing_identity)"
    if [[ "$identity" == "-" ]]; then
      echo "Signing Conductor.app with ad-hoc identity." >&2
    else
      echo "Signing Conductor.app with identity: $identity" >&2
    fi
    local codesign_args=(--force --deep --sign "$identity")
    if [[ "$identity" != "-" && "${CONDUCTOR_ENABLE_HARDENED_RUNTIME:-1}" != "0" ]]; then
      codesign_args+=(--options runtime)
    fi
    if codesign "${codesign_args[@]}" "$APP" >/dev/null; then
      return
    fi
    if [[ "$identity" != "-" ]]; then
      echo "warning: signing with '$identity' failed; falling back to ad-hoc signing." >&2
      codesign --force --deep --sign - "$APP" >/dev/null
    fi
  fi
}

has_signing_identity() {
  local identity="$1"
  security find-identity -p codesigning -v 2>/dev/null | grep -F "\"$identity\"" >/dev/null 2>&1
}

resolve_signing_identity() {
  local requested="${CONDUCTOR_CODE_SIGN_IDENTITY:-${APP_IDENTITY:-}}"
  if [[ -z "$requested" ]]; then
    printf '%s\n' "-"
    return
  fi

  if [[ "$requested" != "auto" ]]; then
    if [[ "$requested" == "-" ]] || has_signing_identity "$requested"; then
      printf '%s\n' "$requested"
      return
    fi
    echo "warning: requested signing identity not found: $requested; falling back to ad-hoc signing" >&2
    printf '%s\n' "-"
    return
  fi

  local candidate
  for candidate in \
    "FlowDesk AI Local Update Test" \
    "CodexBar Development"
  do
    if has_signing_identity "$candidate"; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  candidate="$(
    security find-identity -p codesigning -v 2>/dev/null |
      awk -F '"' '/"Apple Development:|Mac Developer:|Developer ID Application:/ { print $2; exit }'
  )"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return
  fi

  printf '%s\n' "-"
}

main() {
  prepare_dependencies >&2
  build_product >&2
  create_app_layout >&2
  copy_swiftpm_resources >&2
  copy_ghostty_resources >&2
  write_info_plist
  sign_app_bundle >&2
  printf '%s\n' "$APP"
}

main "$@"
