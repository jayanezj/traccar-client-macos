#!/bin/bash
set -euo pipefail

build_root="${1:?Usage: scripts/build.sh /absolute/path/to/external/build-directory [Debug|Release]}"
configuration="${2:-Debug}"
case "$build_root" in
    /*) ;;
    *) echo "The build directory must be an absolute path." >&2; exit 2 ;;
esac
case "$configuration" in
    Debug|Release) ;;
    *) echo "Configuration must be Debug or Release." >&2; exit 2 ;;
esac
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$build_root"

exec xcodebuild \
    -project "$repo_root/TraccarClient.xcodeproj" \
    -scheme TraccarClient \
    -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$build_root/DerivedData" \
    "CLANG_MODULE_CACHE_PATH=$build_root/ModuleCache" \
    "SWIFT_MODULE_CACHE_PATH=$build_root/ModuleCache" \
    build
