#!/bin/sh
# Usage: screenshots.sh <project> <build directory> <sample photos> <output directory>
# Takes the App Store screenshots in the 6.9-inch simulator from scans of the sample photos.
set -eu

project=$1
build=$2
photos=$(cd "$3" && pwd)
output=$4
device="iPhone 17 Pro Max"
bundle=org.roneograph.app

xcodebuild -quiet -project "$project" -scheme Roneograph -configuration Debug \
    -destination "platform=iOS Simulator,name=$device" -derivedDataPath "$build" build
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl uninstall "$device" $bundle 2>/dev/null || true
xcrun simctl install "$device" "$build/Build/Products/Debug-iphonesimulator/Roneograph.app"
xcrun simctl privacy "$device" grant camera $bundle

settings=$(printf '%s' '{"email":"me@example.com","fileNameFormat":{"datePrefix":true,"separator":"dash","lowercase":true}}' | xxd -p | tr -d '\n')
xcrun simctl spawn "$device" defaults write $bundle settings -data "$settings"

mkdir -p "$output"
# The simulator's page detection is only reliable for the first photo of a launch: one launch per photo.
scan() {
    one=$(mktemp -d)
    cp "$1" "$one/"
    SIMCTL_CHILD_RONEOGRAPH_SAMPLE_PHOTOS=$one SIMCTL_CHILD_RONEOGRAPH_SAMPLE_APPEND=$2 xcrun simctl launch --terminate-running-process "$device" $bundle >/dev/null
    sleep 12
    rm -rf "$one"
}
for photo in $(ls "$photos"/*.jpg | tail -n +2); do
    scan "$photo" ""
done
for photo in "$photos"/*.jpg; do
    scan "$photo" "$([ "$photo" = "$(ls "$photos"/*.jpg | head -1)" ] || echo 1)"
done
SIMCTL_CHILD_RONEOGRAPH_SCREEN=review xcrun simctl launch --terminate-running-process "$device" $bundle >/dev/null
sleep 8
xcrun simctl io "$device" screenshot "$output/2-review.png" >/dev/null
for screen in home settings; do
    SIMCTL_CHILD_RONEOGRAPH_SCREEN=$screen xcrun simctl launch --terminate-running-process "$device" $bundle >/dev/null
    sleep 5
    xcrun simctl io "$device" screenshot "$output/$([ $screen = home ] && echo 1 || echo 3)-$screen.png" >/dev/null
done
xcrun simctl status_bar "$device" clear
echo "Screenshots in $output"
