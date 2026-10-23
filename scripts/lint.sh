#!/bin/bash
set -euo pipefail

tools_root="${1:?Usage: scripts/lint.sh /absolute/path/to/tools-directory}"
case "$tools_root" in
    /*) ;;
    *) echo "The tools directory must be an absolute path." >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="0.65.1"
checksum="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
install_root="$tools_root/swiftlint-$version"
binary="$install_root/swiftlint"

if [[ ! -x "$binary" ]]; then
    mkdir -p "$tools_root"
    download_root="$(mktemp -d "$tools_root/swiftlint-download.XXXXXX")"
    trap 'rm -rf "$download_root"' EXIT
    curl --fail --location --silent --show-error --retry 3 \
        --proto '=https' --proto-redir '=https' \
        "https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip" \
        --output "$download_root/portable_swiftlint.zip"
    printf '%s  %s\n' "$checksum" "$download_root/portable_swiftlint.zip" | shasum -a 256 -c -
    mkdir "$download_root/extracted"
    unzip -q "$download_root/portable_swiftlint.zip" -d "$download_root/extracted"
    mkdir -p "$install_root"
    cp "$download_root/extracted/swiftlint" "$binary"
    chmod +x "$binary"
fi

if [[ "$("$binary" version)" != "$version" ]]; then
    echo "Expected SwiftLint $version. Remove $install_root and retry." >&2
    exit 1
fi

cd "$repo_root"
"$binary" lint --strict --no-cache --config .swiftlint.yml
