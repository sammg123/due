#!/bin/bash
# Build Due.app and install it to ~/Applications.
#
# Signs with a stable self-signed identity ("Due Signing") when available. Falls back to
# ad-hoc signing (--sign -). Lecture capture uses the Microphone, and TCC grants stick to
# the signature: with ad-hoc signing macOS re-prompts (one click) after each rebuild; a
# stable "Due Signing" identity makes the grant survive rebuilds.
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

# The desktop widget is an app extension, which only Xcode's build system can produce. It needs
# full Xcode plus XcodeGen (brew install xcodegen); without them Due builds and runs without it.
WIDGET=".build/widget/Build/Products/Release/DueWidget.appex"
BUILD_WIDGET=1
if ! command -v xcodegen > /dev/null 2>&1 || ! xcodebuild -version > /dev/null 2>&1; then
    echo "==> Skipping the desktop widget (needs Xcode and XcodeGen: brew install xcodegen)"
    BUILD_WIDGET=0
fi
if [ "$BUILD_WIDGET" -eq 1 ]; then
    echo "==> Widget: xcodegen + xcodebuild"
    xcodegen generate --spec Widget/project.yml --quiet
    xcodebuild -project Widget/DueWidget.xcodeproj -scheme DueWidget -configuration Release \
        -derivedDataPath .build/widget -quiet build
fi

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/Due"
cp Support/Info.plist "$APP_DIR/Contents/Info.plist"
if [ "$BUILD_WIDGET" -eq 1 ]; then
    # Signed by xcodebuild with its sandbox entitlements; the app signature below seals it as is.
    mkdir -p "$APP_DIR/Contents/PlugIns"
    cp -R "$WIDGET" "$APP_DIR/Contents/PlugIns/"
fi

SIGN_ID="Due Signing"
if security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    echo "==> Signing ($SIGN_ID)"
    if [ "$BUILD_WIDGET" -eq 1 ]; then
        # Same identity inside and out, keeping the widget's sandbox entitlements.
        codesign --force --sign "$SIGN_ID" --identifier com.due.tracker.widget \
            --entitlements Widget/Generated/DueWidget.entitlements "$APP_DIR/Contents/PlugIns/DueWidget.appex"
    fi
    codesign --force --sign "$SIGN_ID" --identifier com.due.tracker "$APP_DIR"
else
    echo "==> Signing (ad-hoc; macOS re-asks for Microphone once after each rebuild)"
    codesign --force --sign - --identifier com.due.tracker "$APP_DIR"
fi

if pgrep -x Due > /dev/null 2>&1; then
    echo "==> Quitting running Due"
    pkill -x Due
    sleep 0.3
fi

# Register right away so the widget shows up in Edit Widgets without waiting for a rescan.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"

echo "==> Done: $APP_DIR"
if [ "$LAUNCH" -eq 1 ]; then
    echo "    open $APP_DIR"
    open "$APP_DIR"
fi
