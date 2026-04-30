#!/usr/bin/env bash
#
# Build a signed, notarized, stapled Minimalist.app and publish it as a
# GitHub Release.
#
# Tag format:
#   v<marketing>+<YYYYMMDD>.<n>
# where <n> is the next available build number for today (1, 2, 3, ...) found
# by scanning existing tags in the repo.
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
#      (Override the profile name with NOTARY_PROFILE=<name> ./make-release.sh.)
#   4. Install the GitHub CLI and authenticate:
#        brew install gh
#        gh auth login
#
# Usage:
#   ./make-release.sh                 # full release: archive → notarize → tag → publish
#   NOTARY_PROFILE=foo ./make-release.sh
#
set -euo pipefail

SCHEME="Minimalist"
CONFIGURATION="Release"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/Minimalist.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/Minimalist.app"
ZIP_FOR_NOTARY="$BUILD_DIR/Minimalist-notary.zip"
INFO_PLIST="Resources/Info.plist"
NOTARY_PROFILE="${NOTARY_PROFILE:-minimalist-notary}"

log() { printf "\n==> %s\n" "$*"; }

# --- Pre-flight checks ----------------------------------------------------

for tool in xcodegen gh; do
    if ! command -v "$tool" >/dev/null; then
        echo "$tool not found. Install with: brew install $tool" >&2
        exit 1
    fi
done

if ! gh auth status >/dev/null 2>&1; then
    echo "Not signed in to GitHub. Run: gh auth login" >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Working tree has uncommitted changes. Commit or stash before releasing." >&2
    exit 1
fi

# --- Version computation --------------------------------------------------

log "Generating app icon"
swift make-icon.swift

log "Regenerating Xcode project"
xcodegen generate

log "Computing release version"
git fetch --tags --quiet 2>/dev/null || echo "    (warning: could not fetch tags; using local tag list)"

DATESTAMP=$(date -u +%Y%m%d)
LAST_BUILD=$(git tag --list "v*+${DATESTAMP}.*" \
    | sed -E "s/.*\+${DATESTAMP}\.//" \
    | grep -E '^[0-9]+$' \
    | sort -n \
    | tail -1 \
    || true)
NEXT_BUILD=$((${LAST_BUILD:-0} + 1))
BUILD_VERSION="${DATESTAMP}.${NEXT_BUILD}"
MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
VERSION="${MARKETING_VERSION}+${BUILD_VERSION}"
TAG="v$VERSION"
ASSET_NAME="Minimalist-${VERSION}.zip"
ZIP_FINAL="$BUILD_DIR/$ASSET_NAME"

echo "    Marketing version: $MARKETING_VERSION"
echo "    Build version:     $BUILD_VERSION"
echo "    Tag:               $TAG"
echo "    Asset:             $ASSET_NAME"

# --- Stamp Info.plist (restored on exit so HEAD stays clean) --------------

ORIGINAL_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
restore_info_plist() {
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ORIGINAL_BUILD" "$INFO_PLIST" 2>/dev/null || true
}
trap restore_info_plist EXIT

log "Stamping CFBundleVersion -> $BUILD_VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$INFO_PLIST"

# --- Build, sign, export --------------------------------------------------

log "Cleaning previous build artifacts"
rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

log "Archiving $SCHEME ($CONFIGURATION) for macOS"
xcodebuild \
    -project Minimalist.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

log "Exporting Developer ID-signed .app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist ExportOptions.plist \
    -allowProvisioningUpdates

log "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# --- Notarize -------------------------------------------------------------

log "Zipping .app for notarization submission"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_FOR_NOTARY"

log "Submitting to Apple notary service (this usually takes 1-5 minutes)"
xcrun notarytool submit "$ZIP_FOR_NOTARY" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

log "Stapling notarization ticket to the .app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# --- Final zip ------------------------------------------------------------

log "Creating final distribution zip"
rm -f "$ZIP_FINAL"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_FINAL"

# --- Tag and publish ------------------------------------------------------

log "Creating git tag $TAG"
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

log "Publishing GitHub release"
gh release create "$TAG" \
    --title "$TAG" \
    --prerelease \
    --generate-notes \
    "$ZIP_FINAL"

# --- Done -----------------------------------------------------------------

log "Done"
printf "    App:     %s\n" "$APP_PATH"
printf "    Zip:     %s\n" "$ZIP_FINAL"
printf "    Tag:     %s\n" "$TAG"
printf "    Release: %s\n" "$(gh release view "$TAG" --json url --jq .url)"
