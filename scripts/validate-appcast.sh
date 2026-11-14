#!/bin/zsh
set -euo pipefail
[[ $# == 6 ]] || { echo "Usage: $0 <appcast> <zip> <arch> <version> <build> <download-url>" >&2; exit 64; }
ROOT="${0:A:h:h}"
APPCAST="$1"; ZIP="$2"; EXPECTED_ARCH="$3"; EXPECTED_VERSION="$4"; EXPECTED_BUILD="$5"; EXPECTED_DOWNLOAD_URL="$6"
xml_value() { xmllint --xpath "string($1)" "$APPCAST"; }
[[ "$(xml_value '(//*[local-name()="item"]/*[local-name()="shortVersionString"])[1]')" == "$EXPECTED_VERSION" ]]
[[ "$(xml_value '(//*[local-name()="item"]/*[local-name()="version"])[1]')" == "$EXPECTED_BUILD" ]]
[[ "$(xml_value '(//*[local-name()="item"]/*[local-name()="minimumSystemVersion"])[1]')" == "13.0" ]]
HARDWARE=$(xml_value '(//*[local-name()="item"]/*[local-name()="hardwareRequirements"])[1]')
case "$EXPECTED_ARCH" in
    arm64) [[ "$HARDWARE" == "arm64" ]] ;;
    x86_64) [[ -z "$HARDWARE" || "$HARDWARE" == "x86_64" ]] ;;
    *) exit 64 ;;
esac
[[ "$(xml_value '(//*[local-name()="item"]/*[local-name()="enclosure"])[1]/@url')" == "$EXPECTED_DOWNLOAD_URL" ]]
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Info.plist")
xcrun swift "$ROOT/scripts/verify-update-signatures.swift" "$PUBLIC_KEY" "$APPCAST" "$ZIP"
echo "Validated $EXPECTED_ARCH appcast for $EXPECTED_VERSION (build $EXPECTED_BUILD)"
