#!/usr/bin/env bash
#
# Xcode Cloud pre-build hook.
#
# Leaves CFBundleShortVersionString (the marketing version, e.g. "1.0.0") alone
# so it stays App-Store-Connect-compatible (must be exactly three integers).
# Stamps the build identifier into CFBundleVersion as <YYYYMMDD>.<CI_BUILD_NUMBER>,
# e.g. 20260429.42. CI_BUILD_NUMBER is the trailing component because Xcode Cloud
# guarantees it increments monotonically per workflow — required by App Store Connect.
set -euo pipefail

if [[ -z "${CI_BUILD_NUMBER:-}" ]]; then
    echo "CI_BUILD_NUMBER not set — not running under Xcode Cloud, skipping."
    exit 0
fi

INFO_PLIST="${CI_PRIMARY_REPOSITORY_PATH:-..}/Resources/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Info.plist not found at $INFO_PLIST" >&2
    exit 1
fi

DATESTAMP=$(date -u +%Y%m%d)
NEW_BUILD="${DATESTAMP}.${CI_BUILD_NUMBER}"

MARKETING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")

echo "Patching $INFO_PLIST"
echo "  CFBundleShortVersionString: $MARKETING (unchanged)"
echo "  CFBundleVersion:            -> $NEW_BUILD"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"
