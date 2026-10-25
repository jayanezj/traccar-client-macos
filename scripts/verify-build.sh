#!/bin/bash
set -euo pipefail

build_root="${1:?Usage: scripts/verify-build.sh /absolute/path/to/build-directory}"
case "$build_root" in
    /*) ;;
    *) echo "The build directory must be an absolute path." >&2; exit 2 ;;
esac
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/scripts/signing-options.sh"

for configuration in Debug Release; do
    app="$build_root/DerivedData/Build/Products/$configuration/Traccar Client macOS.app"
    executable="$app/Contents/MacOS/Traccar Client macOS"
    echo "Verifying $configuration..."
    test "$(lipo -archs "$executable")" = arm64
    test "$(xcrun vtool -show-build "$executable" | awk '/minos/ {print $2}')" = 15.0
    test -n "$(/usr/libexec/PlistBuddy -c 'Print :NSLocationUsageDescription' "$app/Contents/Info.plist")"
    codesign --verify --strict "$app"
    metadata="$(codesign --display --verbose=4 "$app" 2>&1)"
    case "$signing_mode" in
        development)
            if [[ "$metadata" != *"Authority=Apple Development:"* ]]; then
                echo "Expected an Apple Development signature for $configuration." >&2
                exit 1
            fi
            team="$(awk -F= '/^TeamIdentifier=/ {print $2}' <<< "$metadata")"
            if [[ -z "$team" || "$team" == "not set" || -e "$app/Contents/embedded.provisionprofile" ]]; then
                echo "Expected a development Team and no provisioning profile for $configuration." >&2
                exit 1
            fi
            ;;
        adhoc)
            if [[ "$metadata" != *"Signature=adhoc"* ]]; then
                echo "Expected an ad hoc signature for $configuration." >&2
                exit 1
            fi
            ;;
    esac
    echo "Verified $configuration: arm64, macOS 15.0 minimum, $signing_mode signature."
done
