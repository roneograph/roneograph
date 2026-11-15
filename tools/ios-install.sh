#!/bin/sh
# Usage: ios-install.sh <project> <build directory> [device]
set -eu

project=$1
build=$2
device=$(sh "$(dirname "$0")/iphone.sh" "${3:-}")

xcodebuild -quiet -project "$project" -scheme Roneograph -configuration Release \
    -destination "platform=iOS,id=$device" -derivedDataPath "$build" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
if ! xcrun devicectl device install app --device "$device" "$build/Build/Products/Release-iphoneos/Roneograph.app"; then
    echo "Cannot install on the iPhone: unlock it and keep it on the same Wi-Fi as the Mac, or plug it in." >&2
    exit 1
fi
