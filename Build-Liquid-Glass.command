#!/bin/bash
set -euo pipefail

# Personal source build: keep the original app and its updater configuration intact.
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${APP_OUTPUT:-$ROOT/build/Traffic Lights Glass.app}"
BUNDLE_ID="app.trafficlightsplus.glass.local"
PROBE_DIRECTORY=""

cleanup() {
    if [[ -n "$PROBE_DIRECTORY" ]]; then
        rm -rf "$PROBE_DIRECTORY"
    fi
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "请在 Mac 上运行此脚本。需要 Xcode 26 / macOS 26 SDK 或更新版本。" >&2
    exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
    echo "未找到 Apple 开发工具。请先安装 Xcode 26 或更新版本。" >&2
    exit 1
fi

SWIFT_EXECUTABLE="$(xcrun --find swift)"
SWIFTC_EXECUTABLE="$(xcrun --find swiftc)"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export PATH="$(dirname "$SWIFT_EXECUTABLE"):$PATH"
PROBE_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/traffic-lights-glass.XXXXXX")"

cat > "$PROBE_DIRECTORY/GlassSDKProbe.swift" <<'SWIFT'
import AppKit

#if compiler(<6.2)
#error("Native Liquid Glass requires the Swift compiler included with Xcode 26 or newer.")
#endif

@available(macOS 26.0, *)
func verifyGlassSDK() {
    let glass = NSGlassEffectView()
    glass.style = .regular
    glass.cornerRadius = 999
    glass.tintColor = nil
    glass.contentView = NSView()
    let container = NSGlassEffectContainerView()
    container.contentView = NSView()
    container.spacing = 16
}
SWIFT

echo "正在检查原生 Liquid Glass SDK…"
if ! "$SWIFTC_EXECUTABLE" -sdk "$SDKROOT" -typecheck "$PROBE_DIRECTORY/GlassSDKProbe.swift"; then
    echo "当前选中的开发工具不支持此版本的原生玻璃 API。" >&2
    echo "请安装 Xcode 26 或更新版本，并在 Xcode > Settings > Locations 中选择对应 Command Line Tools。" >&2
    exit 1
fi

cd "$ROOT"
echo "正在运行 Swift 测试…"
"$SWIFT_EXECUTABLE" test "$@"

echo "正在构建 Traffic Lights Glass…"
APP_OUTPUT="$APP" SIGNING_IDENTITY=- /bin/zsh "$ROOT/scripts/build-app.sh"

# Remove the upstream feed so Sparkle cannot replace this custom build.
# UpdateController already refuses to start when no valid feed/key is present.
INFO_PLIST="$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$INFO_PLIST"
plutil -replace CFBundleName -string "Traffic Lights Glass" "$INFO_PLIST"
plutil -insert CFBundleDisplayName -string "Traffic Lights Glass" "$INFO_PLIST"
plutil -replace SUEnableAutomaticChecks -bool NO "$INFO_PLIST"
plutil -replace SUAutomaticallyUpdate -bool NO "$INFO_PLIST"
plutil -remove SUFeedURL "$INFO_PLIST"
plutil -remove SUPublicEDKey "$INFO_PLIST"

codesign --force --options runtime --timestamp=none \
    --entitlements "$ROOT/Resources/TrafficLightsPlus.ad-hoc.entitlements" \
    --sign - \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$APP"
codesign --verify --deep --strict "$APP"

[[ "$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")" == "$BUNDLE_ID" ]]
if plutil -extract SUFeedURL raw "$INFO_PLIST" >/dev/null 2>&1; then
    echo "构建检查失败：定制版不应包含上游更新源。" >&2
    exit 1
fi

echo
echo "构建完成：$APP"
echo "请先退出原版 Traffic Lights+，再打开此应用，并为新应用授予辅助功能权限。"
echo "构建不会自动启动或安装应用。"
open -R "$APP"
