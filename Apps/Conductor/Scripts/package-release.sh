#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
cd "$ROOT"

DEFAULT_VERSION=""
if [[ -f "$ROOT/VERSION" ]]; then
  DEFAULT_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
fi
ARG_VERSION=""
ARG_BUILD=""
if [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ARG_VERSION="$1"
  ARG_BUILD="${2:-}"
else
  ARG_BUILD="${1:-}"
fi

VERSION="${CONDUCTOR_RELEASE_VERSION:-${ARG_VERSION:-$DEFAULT_VERSION}}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: CONDUCTOR_RELEASE_VERSION=0.2.0 [CONDUCTOR_RELEASE_BUILD=2026052701] ./Scripts/package-release.sh" >&2
  echo "       ./Scripts/package-release.sh [0.2.0] [build]" >&2
  exit 2
fi

BUILD="${CONDUCTOR_RELEASE_BUILD:-$ARG_BUILD}"
if [[ -z "$BUILD" ]]; then
  BUILD="$(date -u +%Y%m%d%H%M)"
fi

APP_NAME="${CONDUCTOR_RELEASE_APP_NAME:-Conductor}"
PLATFORM="${CONDUCTOR_RELEASE_PLATFORM:-macos}"
ARCH="${CONDUCTOR_RELEASE_ARCH:-$(uname -m)}"
CHANNEL="${CONDUCTOR_RELEASE_CHANNEL:-stable}"
ARTIFACT_ROOT="${CONDUCTOR_RELEASE_ARTIFACT_DIR:-$REPO_ROOT/Artifacts/releases}"
RELEASE_ID="${VERSION}-${BUILD}-${PLATFORM}-${ARCH}"
RELEASE_DIR="$ARTIFACT_ROOT/$RELEASE_ID"
APP_PATH="$ROOT/.build/Conductor.app"
FULL_ZIP="$RELEASE_DIR/${APP_NAME}-${VERSION}-${BUILD}-${PLATFORM}-${ARCH}.zip"
MANIFEST_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}-${BUILD}-${PLATFORM}-${ARCH}.json"
UPDATER_MANIFEST_PATH="$ARTIFACT_ROOT/latest-${CHANNEL}-${PLATFORM}-${ARCH}.json"
GITHUB_UPDATER_MANIFEST_PATH="$RELEASE_DIR/latest-${CHANNEL}-${PLATFORM}-${ARCH}.json"
DELTA_ZIP=""

if [[ -z "${CONDUCTOR_UPDATE_MANIFEST_URL:-}" && -n "${CONDUCTOR_GITHUB_REPO:-}" ]]; then
  export CONDUCTOR_UPDATE_MANIFEST_URL="https://github.com/${CONDUCTOR_GITHUB_REPO}/releases/latest/download/latest-${CHANNEL}-${PLATFORM}-${ARCH}.json"
fi

if [[ "${CONDUCTOR_USE_HOMEBREW_SWIFT:-1}" == "0" ]]; then
  PATH="$(python3 - <<'PY'
import os
print(":".join(part for part in os.environ.get("PATH", "").split(":") if part != "/usr/local/opt/swift/bin"))
PY
)"
  export PATH
elif [[ -x /usr/local/opt/swift/bin/swift ]]; then
  export PATH="/usr/local/opt/swift/bin:$PATH"
fi

mkdir -p "$RELEASE_DIR"

CONDUCTOR_MARKETING_VERSION="$VERSION" \
CONDUCTOR_BUILD_NUMBER="$BUILD" \
CONDUCTOR_BUILD_CONFIGURATION="${CONDUCTOR_BUILD_CONFIGURATION:-release}" \
CONDUCTOR_BUILD_ARCH="${CONDUCTOR_BUILD_ARCH:-$ARCH}" \
"$ROOT/Scripts/build-app-bundle.sh" >/tmp/conductor-release-app-path.txt

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

rm -f "$FULL_ZIP"
ditto -c -k --norsrc --keepParent "$APP_PATH" "$FULL_ZIP"

CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
FULL_SHA="$(shasum -a 256 "$FULL_ZIP" | awk '{print $1}')"
FULL_SIZE="$(stat -f '%z' "$FULL_ZIP")"
MIN_SYSTEM_VERSION="$(plutil -extract LSMinimumSystemVersion raw "$APP_PATH/Contents/Info.plist")"
BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")"

PREVIOUS_APP_INPUT="${CONDUCTOR_PREVIOUS_APP:-}"
PREVIOUS_ZIP_INPUT="${CONDUCTOR_PREVIOUS_ZIP:-}"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/conductor-release.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

PREVIOUS_APP=""
if [[ -n "$PREVIOUS_APP_INPUT" ]]; then
  PREVIOUS_APP="$PREVIOUS_APP_INPUT"
elif [[ -n "$PREVIOUS_ZIP_INPUT" ]]; then
  mkdir -p "$TEMP_ROOT/previous-zip"
  ditto -x -k "$PREVIOUS_ZIP_INPUT" "$TEMP_ROOT/previous-zip"
  PREVIOUS_APP="$(find "$TEMP_ROOT/previous-zip" -maxdepth 2 -name 'Conductor.app' -type d | head -n 1)"
fi

DELTA_JSON="null"
if [[ -n "$PREVIOUS_APP" ]]; then
  if [[ ! -d "$PREVIOUS_APP" ]]; then
    echo "Previous app not found: $PREVIOUS_APP" >&2
    exit 1
  fi

  DELTA_ROOT="$TEMP_ROOT/delta-root"
  DELTA_PAYLOAD="$DELTA_ROOT/payload"
  DELTA_MANIFEST="$DELTA_ROOT/update-delta.json"
  mkdir -p "$DELTA_PAYLOAD"
  DELTA_ZIP="$RELEASE_DIR/${APP_NAME}-${VERSION}-${BUILD}-from-previous-${PLATFORM}-${ARCH}.delta.zip"

  python3 "$ROOT/Scripts/release_delta.py" \
    --old-app "$PREVIOUS_APP" \
    --new-app "$APP_PATH" \
    --payload-dir "$DELTA_PAYLOAD" \
    --manifest "$DELTA_MANIFEST" \
    --version "$VERSION" \
    --build "$BUILD" \
    --created-at "$CREATED_AT"

  rm -f "$DELTA_ZIP"
  ditto -c -k --norsrc "$DELTA_ROOT" "$DELTA_ZIP"
  DELTA_SHA="$(shasum -a 256 "$DELTA_ZIP" | awk '{print $1}')"
  DELTA_SIZE="$(stat -f '%z' "$DELTA_ZIP")"
  DELTA_CHANGED="$(python3 - "$DELTA_MANIFEST" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(len(data.get("changed", [])))
PY
)"
  DELTA_REMOVED="$(python3 - "$DELTA_MANIFEST" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(len(data.get("removed", [])))
PY
)"
  DELTA_JSON="$(python3 - <<PY
import json
print(json.dumps({
    "filename": "$(basename "$DELTA_ZIP")",
    "sha256": "$DELTA_SHA",
    "size": int("$DELTA_SIZE"),
    "changedFiles": int("$DELTA_CHANGED"),
    "removedFiles": int("$DELTA_REMOVED")
}, separators=(",", ":")))
PY
)"
fi

python3 - "$MANIFEST_PATH" <<PY
import json
import sys

delta = json.loads("""$DELTA_JSON""")
manifest = {
    "schemaVersion": 1,
    "app": "$APP_NAME",
    "bundleIdentifier": "$BUNDLE_IDENTIFIER",
    "platform": "$PLATFORM",
    "arch": "$ARCH",
    "channel": "$CHANNEL",
    "version": "$VERSION",
    "build": "$BUILD",
    "createdAt": "$CREATED_AT",
    "minimumSystemVersion": "$MIN_SYSTEM_VERSION",
    "full": {
        "filename": "$(basename "$FULL_ZIP")",
        "sha256": "$FULL_SHA",
        "size": int("$FULL_SIZE")
    },
    "delta": delta
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\\n")
PY

python3 - "$MANIFEST_PATH" "$UPDATER_MANIFEST_PATH" "$RELEASE_ID" <<'PY'
import json
import sys

source_path, updater_path, release_id = sys.argv[1:]
with open(source_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

for key in ("full", "delta"):
    artifact = manifest.get(key)
    if not artifact:
        continue
    filename = artifact.get("filename", "")
    if filename and "://" not in filename and not filename.startswith("/"):
        artifact["filename"] = f"{release_id}/{filename}"

with open(updater_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

python3 - "$MANIFEST_PATH" "$GITHUB_UPDATER_MANIFEST_PATH" <<'PY'
import json
import sys

source_path, github_path = sys.argv[1:]
with open(source_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

with open(github_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

echo "Release artifacts:"
echo "  full:     $FULL_ZIP"
if [[ -n "$DELTA_ZIP" ]]; then
  echo "  delta:    $DELTA_ZIP"
fi
echo "  manifest: $MANIFEST_PATH"
echo "  updater:  $UPDATER_MANIFEST_PATH"
echo "  github:   $GITHUB_UPDATER_MANIFEST_PATH"
