#!/usr/bin/env bash
#
# Xcode Cloud post-build hook.
#
# After a successful Archive action:
#   1. Re-export the archive with Developer ID signing (ExportOptions.plist).
#   2. Submit to Apple's notary service and wait for a verdict.
#   3. Staple the notarization ticket onto the .app.
#   4. Zip the .app and publish it as a new GitHub Release.
#
# Required workflow env vars (App Store Connect → Xcode Cloud → Workflow → Environment):
#   GH_TOKEN          — GitHub fine-grained PAT, Contents: Read and write on this repo (Secret)
#   NOTARY_APPLE_ID   — Apple ID email used for notarization
#   NOTARY_TEAM_ID    — Apple developer team ID (P22P7U46RW)
#   NOTARY_PASSWORD   — App-specific password from appleid.apple.com (Secret)
# Optional:
#   GH_REPO           — owner/name override (defaults to stoicswe/minimalist)
#
# Set Distribution Preparation = None on the Archive action in the workflow editor —
# this script handles distribution itself.
set -euo pipefail

if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
    echo "Not an archive build (CI_XCODEBUILD_ACTION=${CI_XCODEBUILD_ACTION:-unset}); skipping."
    exit 0
fi

if [[ -z "${CI_ARCHIVE_PATH:-}" || ! -d "$CI_ARCHIVE_PATH" ]]; then
    echo "No archive at CI_ARCHIVE_PATH=${CI_ARCHIVE_PATH:-unset}; skipping."
    exit 0
fi

: "${GH_TOKEN:?GH_TOKEN not set in workflow env vars}"
: "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID not set in workflow env vars}"
: "${NOTARY_TEAM_ID:?NOTARY_TEAM_ID not set in workflow env vars}"
: "${NOTARY_PASSWORD:?NOTARY_PASSWORD not set in workflow env vars}"

REPO="${GH_REPO:-stoicswe/minimalist}"
APP_NAME="Minimalist"
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-..}"
EXPORT_OPTS="$REPO_ROOT/ExportOptions.plist"

if [[ ! -f "$EXPORT_OPTS" ]]; then
    echo "ExportOptions.plist not found at $EXPORT_OPTS" >&2
    exit 1
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
EXPORT_DIR="$WORKDIR/export"
mkdir -p "$EXPORT_DIR"

echo "==> Exporting Developer ID-signed .app from archive"
xcodebuild -exportArchive \
    -archivePath "$CI_ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    -allowProvisioningUpdates

APP_PATH="$EXPORT_DIR/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Export did not produce ${APP_NAME}.app at $APP_PATH" >&2
    ls -la "$EXPORT_DIR" >&2 || true
    exit 1
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier" || true

APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
MARKETING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_INFO_PLIST")
VERSION="${MARKETING}+${BUILD}"
TAG="v$VERSION"
ASSET_NAME="${APP_NAME}-${VERSION}.zip"

NOTARY_ZIP="$WORKDIR/notary.zip"
echo "==> Zipping for notarization submission"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

echo "==> Submitting to Apple notary service (typically 1-5 minutes)"
xcrun notarytool submit "$NOTARY_ZIP" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

ZIP_PATH="$WORKDIR/$ASSET_NAME"
echo "==> Creating release zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

API="https://api.github.com/repos/$REPO"
AUTH_HEADER="Authorization: Bearer $GH_TOKEN"
ACCEPT_HEADER="Accept: application/vnd.github+json"
API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"

echo "==> Creating release $TAG on $REPO"
RELEASE_BODY=$(cat <<EOF
{
  "tag_name": "$TAG",
  "name": "$TAG",
  "target_commitish": "${CI_COMMIT:-main}",
  "draft": false,
  "prerelease": true,
  "generate_release_notes": true
}
EOF
)

CREATE_RESPONSE=$(curl -fsSL -X POST \
    -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$API_VERSION_HEADER" \
    "$API/releases" \
    -d "$RELEASE_BODY")

RELEASE_ID=$(echo "$CREATE_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

if [[ -z "$RELEASE_ID" || "$RELEASE_ID" == "None" ]]; then
    echo "Failed to extract release id from response:" >&2
    echo "$CREATE_RESPONSE" >&2
    exit 1
fi

echo "==> Uploading $ASSET_NAME to release $RELEASE_ID"
curl -fsSL -X POST \
    -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$API_VERSION_HEADER" \
    -H "Content-Type: application/zip" \
    --data-binary "@$ZIP_PATH" \
    "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$ASSET_NAME" \
    >/dev/null

echo "==> Done — published $TAG with $ASSET_NAME (notarized + stapled)."
