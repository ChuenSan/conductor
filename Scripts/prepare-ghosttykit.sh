#!/usr/bin/env bash
# 下载并就地准备预编译的 GhosttyKit.xcframework（来自 manaflow-ai/ghostty release）。
# 该二进制（~536MB）不入 git；首次构建前运行本脚本即可。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Vendor/GhosttyKit.xcframework"
SHA="aef980e27b584a9d914f1ff0499b13c6ed1973e0"
FLAVOR="crashsubdir-cmux-crash-v1"
CHECKSUM="c6b8d560ad6b53d73396f80ba6995cb880ae9de9bfe8cae4dbd9ee72629798b5"
URL="https://github.com/manaflow-ai/ghostty/releases/download/xcframework-${SHA}-${FLAVOR}/GhosttyKit.xcframework.tar.gz"

# SwiftPM 的 binaryTarget 要求静态库文件名带 lib 前缀，并与 Info.plist 一致。
normalize_for_swiftpm() {
  local framework="$1"
  local macos_slice="$framework/macos-arm64_x86_64"
  local old_lib="$macos_slice/ghostty-internal.a"
  local new_lib="$macos_slice/libghostty-internal.a"
  local plist="$framework/Info.plist"

  if [[ -f "$old_lib" && ! -f "$new_lib" ]]; then
    mv "$old_lib" "$new_lib"
  fi

  python3 - "$plist" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = plistlib.loads(path.read_bytes())
for library in data.get("AvailableLibraries", []):
    if library.get("SupportedPlatform") == "macos":
        library["BinaryPath"] = "libghostty-internal.a"
        library["LibraryPath"] = "libghostty-internal.a"
path.write_bytes(plistlib.dumps(data, sort_keys=False))
PY
}

if [[ -d "$OUT" ]]; then
  normalize_for_swiftpm "$OUT"
  echo "GhosttyKit already exists: $OUT"
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cmux-ghosttykit.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE="$TMP_DIR/GhosttyKit.xcframework.tar.gz"
EXTRACT="$TMP_DIR/extract"
mkdir -p "$EXTRACT" "$(dirname "$OUT")"

echo "Downloading GhosttyKit.xcframework for ghostty $SHA"
curl --fail --show-error --location \
  --connect-timeout 10 \
  --max-time 600 \
  --retry 3 \
  --retry-delay 2 \
  --retry-all-errors \
  -o "$ARCHIVE" \
  "$URL"

ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL" != "$CHECKSUM" ]]; then
  echo "Checksum mismatch" >&2
  echo "Expected: $CHECKSUM" >&2
  echo "Actual:   $ACTUAL" >&2
  exit 1
fi

tar --no-same-owner -xzf "$ARCHIVE" -C "$EXTRACT"
if [[ ! -d "$EXTRACT/GhosttyKit.xcframework" ]]; then
  echo "Archive did not contain GhosttyKit.xcframework" >&2
  exit 1
fi

mv "$EXTRACT/GhosttyKit.xcframework" "$OUT"
normalize_for_swiftpm "$OUT"
echo "Prepared $OUT"
