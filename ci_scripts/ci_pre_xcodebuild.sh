#!/usr/bin/env bash
#
# Xcode Cloud pre-build hook.
#
# Stamps the version into Resources/Info.plist before the build runs:
#   CFBundleShortVersionString -> <base>-build.<CI_BUILD_NUMBER>   e.g. 1.0.0-build.42
#   CFBundleVersion            -> <CI_BUILD_NUMBER>
#
# <base> is whatever marketing version is already in the plist with any prior
# "-build.N" suffix stripped, so day-to-day you bump 1.0.0 -> 1.1.0 by editing
# project.yml / Info.plist and Xcode Cloud appends the build number.
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

CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BASE="${CURRENT%%-*}"
NEW_MARKETING="${BASE}-build.${CI_BUILD_NUMBER}"

echo "Patching $INFO_PLIST"
echo "  CFBundleShortVersionString: $CURRENT -> $NEW_MARKETING"
echo "  CFBundleVersion:            -> $CI_BUILD_NUMBER"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_MARKETING" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CI_BUILD_NUMBER" "$INFO_PLIST"
