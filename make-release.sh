#!/usr/bin/env bash
#
# Build a signed, notarized, stapled Minimalist.app for distribution.
#
# One-time setup before this works:
#   1. In Xcode → Settings → Accounts, sign in with an Apple ID on team P22P7U46RW
#      and make sure a "Developer ID Application" certificate is installed.
#   2. Create an app-specific password at https://appleid.apple.com
#      → Sign-In and Security → App-Specific Passwords.
#   3. Store notarytool credentials in your login keychain (one time):
#        xcrun notarytool store-credentials minimalist-notary \
#          --apple-id you@example.com \
#          --team-id P22P7U46RW \
#          --password <app-specific-password>
#      (The profile name "minimalist-notary" is what this script expects;
#       override with NOTARY_PROFILE=<name> ./make-release.sh if you prefer.)
#
# Usage:
#   ./make-release.sh          # full archive → notarize → staple → zip
#   NOTARY_PROFILE=foo ./make-release.sh
#
set -euo pipefail

TEAM_ID="P22P7U46RW"
SCHEME="Minimalist"
CONFIGURATION="Release"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/Minimalist.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/Minimalist.app"
ZIP_FOR_NOTARY="$BUILD_DIR/Minimalist-notary.zip"
ZIP_FINAL="$BUILD_DIR/Minimalist.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-minimalist-notary}"

log() { printf "\n==> %s\n" "$*"; }

if ! command -v xcodegen >/dev/null; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

log "Generating app icon"
swift make-icon.swift

log "Regenerating Xcode project"
xcodegen generate

log "Cleaning previous build artifacts"
rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

log "Archiving $SCHEME ($CONFIGURATION) for macOS"
# `-allowProvisioningUpdates` lets Xcode regenerate the dev profile when
# capabilities change (e.g. when we add the iCloud KVS entitlement). Without
# it the archive fails on the first run after an entitlement bump.
xcodebuild \
    -project Minimalist.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

log "Exporting Developer ID–signed .app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist ExportOptions.plist \
    -allowProvisioningUpdates

log "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

log "Zipping .app for notarization submission"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_FOR_NOTARY"

log "Submitting to Apple notary service (this usually takes 1–5 minutes)"
xcrun notarytool submit "$ZIP_FOR_NOTARY" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

log "Stapling notarization ticket to the .app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

log "Creating final distribution zip"
rm -f "$ZIP_FINAL"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_FINAL"

log "Done"
printf "    App: %s\n" "$APP_PATH"
printf "    Zip: %s\n" "$ZIP_FINAL"
printf "\nHand '%s' to your recipient — it should open with a double-click on macOS 26.\n" "$ZIP_FINAL"
