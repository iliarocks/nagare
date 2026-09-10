#!/bin/bash
set -euo pipefail
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
expected_xcode_build="${EXPECTED_XCODE_BUILD:-27A266a}"
actual_xcode_build="$(xcodebuild -version | awk '/Build version/ {print $3}')"
if [[ "$actual_xcode_build" != "$expected_xcode_build" ]]; then
    echo "Select Xcode 27 RC (27A266a), or explicitly set EXPECTED_XCODE_BUILD for a reviewed toolchain update." >&2
    exit 1
fi
platform="${1:-macos}"
suite="${2:-unit}"
case "$platform" in
    ios) destination="${TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17}" ;;
    macos) destination="${TEST_DESTINATION:-platform=macOS}" ;;
    *) echo "Unsupported platform: $platform" >&2; exit 2 ;;
esac
args=(-project Nagare.xcodeproj -scheme Nagare -configuration Debug
    -destination "$destination" -derivedDataPath ".build/derived/$platform"
    -parallel-testing-enabled NO)
bash Scripts/lint-imports.sh
case "$suite" in
    build) exec xcodebuild "${args[@]}" -allowProvisioningUpdates build ;;
    unit) args+=(-only-testing:NagareTests) ;;
    ui) args+=(-only-testing:NagareUITests) ;;
    all) ;;
    *) echo "Usage: $0 [ios|macos] [unit|ui|all|build]" >&2; exit 2 ;;
esac
result=".build/results/$platform-$suite.xcresult"
mkdir -p .build/results
rm -rf "$result"
exec xcodebuild "${args[@]}" -resultBundlePath "$result" test
