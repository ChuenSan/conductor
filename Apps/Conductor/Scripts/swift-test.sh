#!/bin/bash
# Runs `swift test` on machines that have only the Command Line Tools (no Xcode).
#
# On a CLT-only install there is no XCTest, and Swift Testing ships at a
# non-default location, so plain `swift test` fails to find the `Testing`
# module / its runtime dylib. This wrapper points the compiler, linker, and
# dynamic loader at the CLT copies. It is self-contained (no symlinks in
# .build, survives `swift package clean`).
#
# Usage: Apps/Conductor/Scripts/swift-test.sh [extra swift test args]
#   e.g. ./Scripts/swift-test.sh --filter SanityTests
set -euo pipefail

CLT="$(xcode-select -p 2>/dev/null || echo /Library/Developer/CommandLineTools)"
FRAMEWORKS="$CLT/Library/Developer/Frameworks"
TESTING_LIB="$CLT/Library/Developer/usr/lib"

# If a real Xcode toolchain is in use (XCTest present), just run plain swift test.
if [ -d "$CLT/Library/Frameworks/XCTest.framework" ] || [ -d "$CLT/../SharedFrameworks/XCTest.framework" ]; then
  exec swift test "$@"
fi

if [ ! -d "$FRAMEWORKS/Testing.framework" ]; then
  echo "swift-test.sh: Testing.framework not found at $FRAMEWORKS" >&2
  echo "Falling back to plain 'swift test'." >&2
  exec swift test "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Bake absolute rpaths into the test binary so the runtime loader finds
# Testing.framework and lib_TestingInterop.dylib without DYLD_* env vars (which
# SIP strips when launching the system swiftpm-testing-helper).
exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -L -Xlinker "$TESTING_LIB" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$TESTING_LIB" \
    "$@"
