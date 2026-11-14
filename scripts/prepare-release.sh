#!/bin/zsh
# Build both architectures, package, sign and validate. Never publishes or exports keys.
set -euo pipefail
ROOT="${0:A:h:h}"
source "$ROOT/scripts/release-config.sh"
cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
TAG="v$VERSION"
OUT="$ROOT/build/releases/$TAG"
NOTES="$ROOT/docs/releases/$VERSION.md"
[[ "$BUILD" == <-> && -f "$NOTES" ]] || { echo "Invalid release metadata or missing notes" >&2; exit 1; }
[[ ! -e "$OUT" ]] || { echo "Release output already exists: $OUT (preserve it or choose a new version)" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit the release source before packaging" >&2; exit 1; }
SOURCE_COMMIT=$(git rev-parse HEAD)
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
"$ROOT/scripts/check-glass-sdk.sh"
swift test "$@"
TOOLS="${SPARKLE_TOOLS_DIR:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}"
[[ -x "$TOOLS/generate_appcast" ]] || { echo "Missing Sparkle tools; resolve Swift packages first" >&2; exit 1; }
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Info.plist)
KEYCHAIN_PUBLIC=$("$TOOLS/generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -p)
[[ "$PUBLIC_KEY" == "$KEYCHAIN_PUBLIC" ]] || { echo "The Keychain signing key does not match this application's public key" >&2; exit 1; }
mkdir -p "$ROOT/build/releases"
STAGE=$(mktemp -d "$ROOT/build/releases/.$TAG.XXXXXXXX")
trap 'rm -rf "$STAGE"' EXIT
for ARCH in arm64 x86_64; do
    APP="$ROOT/.build/release-$TAG/$ARCH/$RELEASE_APP_NAME.app"
    NAME="Traffic-Lights-Glass-$VERSION-$ARCH"
    TARGET_ARCH="$ARCH" APP_OUTPUT="$APP" "$ROOT/scripts/build-app.sh"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/$NAME.zip"
    DMG_ROOT="$STAGE/dmg-$ARCH"
    mkdir "$DMG_ROOT"
    ditto "$APP" "$DMG_ROOT/$RELEASE_APP_NAME.app"
    ln -s /Applications "$DMG_ROOT/Applications"
    hdiutil create -volname "$RELEASE_APP_NAME $VERSION ($ARCH)" -srcfolder "$DMG_ROOT" -fs APFS -format UDZO -ov "$STAGE/$NAME.dmg"
    rm -rf "$DMG_ROOT"
    FEED_ROOT="$STAGE/feed-$ARCH"
    mkdir "$FEED_ROOT"
    cp "$STAGE/$NAME.zip" "$FEED_ROOT/$NAME.zip"
    cp "$NOTES" "$FEED_ROOT/$NAME.md"
    "$TOOLS/generate_appcast" --account "$SPARKLE_KEY_ACCOUNT" --maximum-deltas 0 --embed-release-notes \
        --download-url-prefix "https://github.com/$RELEASE_REPOSITORY/releases/download/$TAG/" \
        --link "https://github.com/$RELEASE_REPOSITORY/releases/tag/$TAG" \
        -o "$STAGE/appcast-$ARCH.xml" "$FEED_ROOT"
    rm -rf "$FEED_ROOT"
    "$ROOT/scripts/validate-appcast.sh" "$STAGE/appcast-$ARCH.xml" "$STAGE/$NAME.zip" "$ARCH" "$VERSION" "$BUILD" \
        "https://github.com/$RELEASE_REPOSITORY/releases/download/$TAG/$NAME.zip"
    "$ROOT/scripts/validate-release-asset.sh" "$STAGE/$NAME.zip" "$ARCH" "$VERSION" "$BUILD"
done
(
    cd "$STAGE"
    shasum -a 256 -- *.zip *.dmg appcast-*.xml > SHA256SUMS.txt
)
printf '%s\n' "$SOURCE_COMMIT" > "$STAGE/SOURCE_COMMIT.txt"
cp "$NOTES" "$STAGE/RELEASE_NOTES.md"
mv "$STAGE" "$OUT"
trap - EXIT
echo "Release prepared and validated: $OUT"
echo "Next: scripts/create-release-draft.sh (uploads a reviewable draft)"
