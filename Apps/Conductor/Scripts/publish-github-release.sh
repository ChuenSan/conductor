#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'USAGE'
Usage:
  ./Scripts/publish-github-release.sh /path/to/Artifacts/releases/<version>-<build>-macos-<arch> [tag]

Environment:
  CONDUCTOR_GITHUB_REPO=owner/repo   Required GitHub repository for the release.
  CONDUCTOR_RELEASE_NOTES=path       Optional release notes file.
USAGE
  exit "${1:-2}"
}

release_dir="${1:-}"
tag="${2:-}"
if [[ "$release_dir" == "-h" || "$release_dir" == "--help" ]]; then
  usage 0
fi
[[ -n "$release_dir" ]] || usage
[[ -d "$release_dir" ]] || { echo "Release directory not found: $release_dir" >&2; exit 1; }

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: brew install gh" >&2
  exit 1
fi

manifest_path="$(find "$release_dir" -maxdepth 1 -type f -name 'Conductor-*.json' | head -n 1)"
[[ -n "$manifest_path" ]] || { echo "Version manifest not found in $release_dir" >&2; exit 1; }

version="$(python3 - "$manifest_path" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])
PY
)"
build="$(python3 - "$manifest_path" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["build"])
PY
)"
channel="$(python3 - "$manifest_path" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("channel", "stable"))
PY
)"
arch="$(python3 - "$manifest_path" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("arch", "arm64"))
PY
)"
tag="${tag:-v${version}-${build}}"
title="Conductor ${version} (${build})"

repo="${CONDUCTOR_GITHUB_REPO:-}"
[[ -n "$repo" ]] || { echo "Set CONDUCTOR_GITHUB_REPO=owner/repo before publishing." >&2; exit 1; }

assets=()
while IFS= read -r asset; do
  assets+=("$asset")
done < <(find "$release_dir" -maxdepth 1 -type f \( -name '*.zip' -o -name "latest-${channel}-macos-*.json" \) | sort)
[[ ${#assets[@]} -gt 0 ]] || { echo "No GitHub release assets found in $release_dir" >&2; exit 1; }

notes_file="${CONDUCTOR_RELEASE_NOTES:-}"
temp_notes=""
if [[ -z "$notes_file" ]]; then
  temp_notes="$(mktemp "${TMPDIR:-/tmp}/conductor-release-notes.XXXXXX")"
  notes_file="$temp_notes"
  {
    echo "Conductor ${version} (${build})"
    echo
    echo "- Full app bundle update"
    echo "- Incremental update package when available"
    echo "- In-app updater manifest for ${channel}"
  } > "$notes_file"
fi
trap '[[ -n "${temp_notes:-}" ]] && rm -f "$temp_notes"' EXIT

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release upload "$tag" "${assets[@]}" --repo "$repo" --clobber
else
  gh release create "$tag" "${assets[@]}" \
    --repo "$repo" \
    --title "$title" \
    --notes-file "$notes_file" \
    --latest
fi

echo "GitHub release ready:"
echo "  repo: $repo"
echo "  tag:  $tag"
echo "  url:  https://github.com/$repo/releases/latest/download/latest-${channel}-macos-${arch}.json"
