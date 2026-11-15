#!/bin/sh
# Usage: iphone.sh [device name, identifier or UDID]
# Prints the UDID of the given paired iPhone, or of the first one.
set -eu

device=${1:-}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

xcrun devicectl list devices -q --json-output "$tmp/devices.json" >/dev/null
udid=$(jq -r --arg device "$device" '[.result.devices[]
    | select(.hardwareProperties.deviceType == "iPhone" and .connectionProperties.pairingState == "paired")
    | select($device == "" or .identifier == $device or .hardwareProperties.udid == $device or .deviceProperties.name == $device)
    ][0].hardwareProperties.udid // empty' "$tmp/devices.json")
if [ -z "$udid" ]; then
    echo "No paired iPhone found${device:+ matching $device}." >&2
    exit 1
fi
echo "$udid"
