#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
flutter_sdk="${FLUTTER_SDK:-$HOME/Library/Developer/flutter}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$project_dir/scripts/xcode-tools:$flutter_sdk/bin:$PATH"
export NO_PROXY="${NO_PROXY:+$NO_PROXY,}localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"
cd "$project_dir/app"
exec "$flutter_sdk/bin/flutter" "$@"
