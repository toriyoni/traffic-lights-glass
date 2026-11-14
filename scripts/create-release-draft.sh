#!/bin/zsh
# Upload an already validated release as a draft. Publishing is a separate action.
set -euo pipefail
ROOT="${0:A:h:h}"
source "$ROOT/scripts/release-config.sh"
cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
TAG="v$VERSION"
OUT="$ROOT/build/releases/$TAG"
[[ -d "$OUT" ]]
[[ "$(cat "$OUT/SOURCE_COMMIT.txt")" == "$(git rev-parse HEAD)" ]] || { echo "Package source differs from HEAD" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]]
[[ "$(git rev-parse "$TAG^{commit}")" == "$(git rev-parse HEAD)" ]]
for ARCH in arm64 x86_64; do
    NAME="Traffic-Lights-Glass-$VERSION-$ARCH"
    "$ROOT/scripts/validate-appcast.sh" "$OUT/appcast-$ARCH.xml" "$OUT/$NAME.zip" "$ARCH" "$VERSION" "$BUILD" \
        "https://github.com/$RELEASE_REPOSITORY/releases/download/$TAG/$NAME.zip"
done
(cd "$OUT"; shasum -a 256 -c SHA256SUMS.txt)
# Compare against the actual public update channel before allowing an upload.
PREVIOUS=$(mktemp)
trap 'rm -f "$PREVIOUS"' EXIT
HTTP_CODE=$(curl --fail-with-body --silent --show-error --location --output "$PREVIOUS" --write-out '%{http_code}' "$(release_feed_url arm64)" || true)
case "$HTTP_CODE" in
    200)
        PREVIOUS_BUILD=$(xmllint --xpath 'string((//*[local-name()="item"]/*[local-name()="version"])[1])' "$PREVIOUS")
        [[ "$PREVIOUS_BUILD" == <-> && "$BUILD" -gt "$PREVIOUS_BUILD" ]] || { echo "Build number must increase" >&2; exit 1; }
        ;;
    404) [[ "$VERSION" == "1.0.0" && "$BUILD" == "10" ]] ;;
    *) echo "Cannot verify the previous update channel (HTTP $HTTP_CODE)" >&2; exit 1 ;;
esac
gh release create "$TAG" --repo "$RELEASE_REPOSITORY" --verify-tag --draft \
    --title "$RELEASE_APP_NAME $VERSION" --notes-file "$OUT/RELEASE_NOTES.md" \
    "$OUT"/*.zip "$OUT"/*.dmg "$OUT"/appcast-*.xml "$OUT/SHA256SUMS.txt"
