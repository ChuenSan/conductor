#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"
PART="${1:-patch}"
DRY_RUN=0

if [[ "${2:-}" == "--dry-run" ]] || [[ "$PART" == "--dry-run" ]]; then
  DRY_RUN=1
  if [[ "$PART" == "--dry-run" ]]; then
    PART="patch"
  fi
fi

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing VERSION file at $VERSION_FILE" >&2
  exit 1
fi

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "VERSION must be semver major.minor.patch, got: $CURRENT" >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$PART" in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  patch)
    patch=$((patch + 1))
    ;;
  [0-9]*.[0-9]*.[0-9]*)
    if [[ ! "$PART" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      echo "Version must be semver major.minor.patch, got: $PART" >&2
      exit 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
    ;;
  *)
    echo "Usage: ./Scripts/bump-version.sh [major|minor|patch|x.y.z] [--dry-run]" >&2
    exit 2
    ;;
esac

NEXT="$major.$minor.$patch"
if [[ "$DRY_RUN" == "0" ]]; then
  printf '%s\n' "$NEXT" > "$VERSION_FILE"
fi

echo "$CURRENT -> $NEXT"
