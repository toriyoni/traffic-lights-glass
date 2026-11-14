#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "请在 Mac 上运行。需要 Xcode 26 / macOS 26 SDK 或更新版本。" >&2
    exit 1
fi
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export PATH="$(dirname "$(xcrun --find swift)"):$PATH"
cd "$ROOT"
echo "正在检查原生 Liquid Glass SDK…"
"$ROOT/scripts/check-glass-sdk.sh"
echo "正在运行 Swift 测试…"
swift test "$@"
echo "正在构建 Traffic Lights Glass…"
/bin/zsh "$ROOT/scripts/build-app.sh"
echo "构建完成：${APP_OUTPUT:-$ROOT/build/Traffic Lights Glass.app}"
echo "此构建使用本仓库 Release 更新源，不会接收原版 Traffic Lights+ 更新。"
open -R "${APP_OUTPUT:-$ROOT/build/Traffic Lights Glass.app}"
