#!/bin/sh
# Usage: testflight.sh <project> <build directory>
# Archives a Release build and uploads it to App Store Connect, numbered with the current UTC time.
set -eu

project=$1
build=$2
archive=$build/Roneograph.xcarchive
version=$(date -u +%Y%m%d.%H%M)
options=$(mktemp)
trap 'rm -f "$options"' EXIT

cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
PLIST

rm -rf "$archive"
xcodebuild -quiet -project "$project" -scheme Roneograph -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$version" archive
xcodebuild -quiet -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
    -exportPath "$build/export" -allowProvisioningUpdates
echo "Uploaded build $version to App Store Connect."
