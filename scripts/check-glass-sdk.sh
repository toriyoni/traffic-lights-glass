#!/bin/bash
set -euo pipefail
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/traffic-glass-sdk.XXXXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
sdk_path="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
cat > "$probe_dir/GlassSDKProbe.swift" <<'SWIFT'
import AppKit
import SwiftUI
#if compiler(<6.2)
#error("Native Liquid Glass requires Xcode 26 / Swift 6.2 or newer.")
#endif
@available(macOS 26.0, *)
func verifyGlassSDK() -> some View {
    let glass = NSGlassEffectView()
    glass.style = .regular
    glass.cornerRadius = 999
    return Color.clear.glassEffect(.regular, in: Capsule())
}
SWIFT
xcrun swiftc -sdk "$sdk_path" -typecheck "$probe_dir/GlassSDKProbe.swift"
