#!/bin/bash
set -euo pipefail

build_root="${1:?Usage: scripts/test.sh /absolute/path/to/external/build-directory}"
case "$build_root" in
    /*) ;;
    *) echo "The build directory must be an absolute path." >&2; exit 2 ;;
esac
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/scripts/signing-options.sh"
mkdir -p "$build_root/TestResults"
result_root="$(mktemp -d "$build_root/TestResults/run.XXXXXX")"

echo "Test results: $result_root/Configuration.xcresult"
exec xcodebuild \
    -project "$repo_root/TraccarClient.xcodeproj" \
    -scheme TraccarClient \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -parallel-testing-enabled NO \
    -derivedDataPath "$build_root/DerivedData" \
    -resultBundlePath "$result_root/Configuration.xcresult" \
    "CLANG_MODULE_CACHE_PATH=$build_root/ModuleCache" \
    "SWIFT_MODULE_CACHE_PATH=$build_root/ModuleCache" \
    "${signing_options[@]}" \
    test
