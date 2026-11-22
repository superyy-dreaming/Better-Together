#!/bin/sh
set -eu

# Xcode GUI builds do not pass through flutter.sh. Native Dart hooks retain
# PATH but strip DEVELOPER_DIR, so expose the same SDK resolver to both entrypoints.
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$script_dir/xcode-tools:$PATH"
export NO_PROXY="${NO_PROXY:+$NO_PROXY,}localhost,127.0.0.1,::1"
export no_proxy="$NO_PROXY"

if [ "${PLATFORM_NAME:-}" = "iphonesimulator" ] && [ "${CONFIGURATION:-Debug}" != "Debug" ]; then
  echo "error: Flutter iOS Simulator requires Debug. Select the 'Better Together Simulator' scheme; use 'Better Together Device' for a physical iPhone." >&2
  exit 1
fi

if [ -z "${FLUTTER_ROOT:-}" ] || [ ! -f "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" ]; then
  echo "error: Flutter SDK is unavailable. Run bash scripts/flutter.sh pub get from the project root." >&2
  exit 1
fi

exec /bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" "$@"
