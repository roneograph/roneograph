#!/bin/sh
# Usage: spike-pull.sh <bundle identifier> <destination> [device]
# Copies the camera spike sessions from the app's Documents/Spike folder on the iPhone.
set -eu

bundle=$1
destination=$2
device=$(sh "$(dirname "$0")/iphone.sh" "${3:-}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! xcrun devicectl device info files --device "$device" --domain-type appDataContainer --domain-identifier "$bundle" \
    --subdirectory Documents/Spike -q --json-output "$tmp/files.json" >/dev/null 2>"$tmp/error"; then
    cat "$tmp/error" >&2
    echo "Cannot reach the iPhone: unlock it and keep it on the same Wi-Fi as the Mac, or plug it in." >&2
    exit 1
fi
jq -r '.result.files[] | select(.fileSize != null and .fileSize > 0) | .relativePath' "$tmp/files.json" | while read -r file; do
    mkdir -p "$destination/$(dirname "$file")"
    [ -f "$destination/$file" ] || xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" -q --source "Documents/Spike/$file" --destination "$destination/$file" >/dev/null
done
echo "Copied to $destination"
