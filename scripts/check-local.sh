#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: scripts/check-local.sh /absolute/path/to/validation-directory [primary|macos15]"
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    usage
    exit 0
fi
if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage >&2
    exit 2
fi

validation_root="$1"
profile="${2:-primary}"
case "$validation_root" in
    /*) ;;
    *) echo "The validation directory must be an absolute path." >&2; exit 2 ;;
esac
case "$profile" in
    primary) toolchain=(27.1 27A9275 27.0 27) ;;
    macos15) toolchain=(26.3 17C529 26.2 15) ;;
    *) echo "Profile must be primary or macos15." >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
trap 'status=$?; echo "Local checks failed (exit $status)." >&2; exit "$status"' ERR

echo "Checking toolchain ($profile)..."
scripts/verify-toolchain.sh "${toolchain[@]}"

echo "Checking shell syntax and Git whitespace..."
for script in scripts/*.sh; do
    bash -n "$script"
done
git diff --check
git diff --cached --check

echo "Running SwiftLint..."
scripts/lint.sh "$validation_root/tools"

for configuration in Debug Release; do
    echo "Building $configuration..."
    scripts/build.sh "$validation_root/build" "$configuration"
done

echo "Checking application binaries and signatures..."
scripts/verify-build.sh "$validation_root/build"

echo "Local checks passed ($profile): lint, Debug, Release, arm64, macOS 15.0 minimum and signatures."
echo "Hosted workflow execution and manual application checks remain separate."
