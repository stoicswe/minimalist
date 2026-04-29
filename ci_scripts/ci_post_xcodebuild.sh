#!/usr/bin/env bash
#
# Xcode Cloud post-build hook.
#
# After a successful Archive action, zip the .app and publish it as a new
# GitHub Release tagged v<CFBundleShortVersionString>.
#
# Required workflow env vars (configure under Xcode Cloud → Workflow → Environment):
#   GH_TOKEN  — GitHub fine-grained PAT with "Contents: Read and write" on this repo (mark as Secret)
# Optional:
#   GH_REPO   — owner/name override (defaults to stoicswe/minimalist)
#
# Notarization: enable the "Notarize" post-action on the Archive step in the
# Xcode Cloud workflow editor so the .app inside the archive is already
# stapled by the time this script runs.
set -euo pipefail

if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
    echo "Not an archive build (CI_XCODEBUILD_ACTION=${CI_XCODEBUILD_ACTION:-unset}); skipping release upload."
    exit 0
fi

if [[ -z "${CI_ARCHIVE_PATH:-}" || ! -d "$CI_ARCHIVE_PATH" ]]; then
    echo "No archive at CI_ARCHIVE_PATH=${CI_ARCHIVE_PATH:-unset}; skipping."
    exit 0
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "GH_TOKEN not set in Xcode Cloud workflow env vars; cannot upload to GitHub Releases." >&2
    exit 1
fi

REPO="${GH_REPO:-stoicswe/minimalist}"
APP_NAME="Minimalist"
APP_PATH="$CI_ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Did not find ${APP_NAME}.app at $APP_PATH" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
TAG="v$VERSION"
ASSET_NAME="${APP_NAME}-${VERSION}.zip"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
ZIP_PATH="$WORKDIR/$ASSET_NAME"

echo "Zipping $APP_PATH -> $ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

API="https://api.github.com/repos/$REPO"
AUTH_HEADER="Authorization: Bearer $GH_TOKEN"
ACCEPT_HEADER="Accept: application/vnd.github+json"
API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"

echo "Creating release $TAG on $REPO"
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

echo "Uploading $ASSET_NAME to release $RELEASE_ID"
curl -fsSL -X POST \
    -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$API_VERSION_HEADER" \
    -H "Content-Type: application/zip" \
    --data-binary "@$ZIP_PATH" \
    "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$ASSET_NAME" \
    >/dev/null

echo "Done — published $TAG with $ASSET_NAME attached."
