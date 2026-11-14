# Shared by build, packaging, validation and release scripts.
RELEASE_REPOSITORY="toriyoni/traffic-lights-glass"
RELEASE_APP_NAME="Traffic Lights Glass"
# Keep the installed development identity so preferences and AX access survive.
RELEASE_BUNDLE_ID="app.trafficlightsplus.glass.local"
SPARKLE_KEY_ACCOUNT="app.trafficlightsplus.glass.local"
release_feed_url() {
    printf 'https://github.com/%s/releases/latest/download/appcast-%s.xml' "$RELEASE_REPOSITORY" "$1"
}
