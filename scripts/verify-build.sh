#!/bin/bash
set -euo pipefail

build_root="${1:?Usage: scripts/verify-build.sh /absolute/path/to/build-directory}"
case "$build_root" in
    /*) ;;
    *) echo "The build directory must be an absolute path." >&2; exit 2 ;;
esac

for configuration in Debug Release; do
    app="$build_root/DerivedData/Build/Products/$configuration/Traccar Client macOS.app"
    executable="$app/Contents/MacOS/Traccar Client macOS"
    echo "Verifying $configuration..."
    test "$(lipo -archs "$executable")" = arm64
    test "$(xcrun vtool -show-build "$executable" | awk '/minos/ {print $2}')" = 15.0
    codesign --verify --strict "$app"
done
