#!/bin/sh
# Usage: scans-pull.sh <bundle identifier> <destination> [device]
# Copies the scans (photos, flattened pages, previews, scan.json) from the app on the iPhone, to tune the cleanup on real pages.
set -eu

bundle=$1
destination=$2
device=$(sh "$(dirname "$0")/iphone.sh" "${3:-}")
folder="Library/Application Support/Scans"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! xcrun devicectl device info files --device "$device" --domain-type appDataContainer --domain-identifier "$bundle" \
    --subdirectory "$folder" -q --json-output "$tmp/files.json" >/dev/null 2>"$tmp/error"; then
    cat "$tmp/error" >&2
    echo "Cannot reach the iPhone: unlock it and keep it on the same Wi-Fi as the Mac, or plug it in." >&2
    exit 1
fi
jq -r '.result.files[] | select(.resources.isDirectory == false) | .relativePath' "$tmp/files.json" | while read -r file; do
    mkdir -p "$destination/$(dirname "$file")"
    [ -f "$destination/$file" ] && [ "$(basename "$file")" != scan.json ] || xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" -q --source "$folder/$file" --destination "$destination/$file" >/dev/null
done
echo "Copied to $destination"
