#!/bin/bash
set -euo pipefail

expected_version="${1:?Usage: scripts/verify-toolchain.sh XCODE_VERSION XCODE_BUILD SDK_VERSION OS_MAJOR}"
expected_build="${2:?Missing Xcode build}"
expected_sdk="${3:?Missing macOS SDK version}"
expected_os="${4:?Missing macOS major version}"

[[ "$(uname -m)" == arm64 ]] || { echo "An arm64 host is required." >&2; exit 1; }
[[ "$(sw_vers -productVersion | cut -d . -f 1)" == "$expected_os" ]] || {
    echo "Expected macOS $expected_os." >&2; exit 1;
}

actual_xcode="$(xcodebuild -version)"
printf '%s\n' "$actual_xcode"
[[ "$actual_xcode" == "$(printf 'Xcode %s\nBuild version %s' "$expected_version" "$expected_build")" ]] || {
    echo "Unexpected Xcode version/build." >&2; exit 1;
}

actual_sdk="$(xcrun --sdk macosx --show-sdk-version)"
[[ "$actual_sdk" == "$expected_sdk" ]] || {
    echo "Expected macOS SDK $expected_sdk; found $actual_sdk." >&2; exit 1;
}

sw_vers
xcrun swift --version
printf 'Architecture: %s\nmacOS SDK: %s\n' "$(uname -m)" "$actual_sdk"
