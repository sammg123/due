#!/bin/bash
# Build Due.app and install it to ~/Applications.
#
# Signs with a stable self-signed identity ("Due Signing") when available. Falls back to
# ad-hoc signing (--sign -), which is fine here: Due needs no TCC-gated permissions
# (no Accessibility, no Microphone, no camera, nothing to re-grant after a rebuild).
set -euo pipefail
cd "$(dirname "$0")"

APP_DIR="$HOME/Applications/Due.app"
LAUNCH=1
RUN_TESTS=0

for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=0 ;;
        --test) RUN_TESTS=1 ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--test] [--no-launch]" >&2
            exit 1
            ;;
    esac
done

if [ "$RUN_TESTS" -eq 1 ]; then
    echo "==> swift test"
    swift test
fi

echo "==> swift build -c release"
swift build -c release

BIN=".build/release/Due"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/Due"
cp Support/Info.plist "$APP_DIR/Contents/Info.plist"

SIGN_ID="Due Signing"
if security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    echo "==> Signing ($SIGN_ID)"
    codesign --force --sign "$SIGN_ID" --identifier com.due.tracker "$APP_DIR"
else
    echo "==> Signing (ad-hoc; fine, Due needs no TCC-gated permissions)"
    codesign --force --sign - --identifier com.due.tracker "$APP_DIR"
fi

if pgrep -x Due > /dev/null 2>&1; then
    echo "==> Quitting running Due"
    pkill -x Due
    sleep 0.3
fi

echo "==> Done: $APP_DIR"
if [ "$LAUNCH" -eq 1 ]; then
    echo "    open $APP_DIR"
    open "$APP_DIR"
fi
