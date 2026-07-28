#!/usr/bin/env bash
#
# Build an unsigned OffiCraft.ipa.
#
# Signing needs a team and a provisioning profile that covers both the app and
# its widget extension, which is a per-developer thing. So this archives with
# signing off and packages the .app by hand — the usual way to produce an
# inspectable / resignable build.
#
# Usage: ./scripts/build-ipa.sh [Debug|Release]

set -euo pipefail

CONFIGURATION="${1:-Release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
ARCHIVE="$BUILD_DIR/OffiCraft.xcarchive"

cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Install Xcode (not just the Command Line Tools)." >&2
  exit 1
fi

if ! xcodebuild -showsdks 2>/dev/null | grep -q "iphoneos"; then
  echo "error: no iOS SDK. Open Xcode once to finish installing its components." >&2
  exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> regenerating project"
  xcodegen generate --spec project.yml
fi

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "==> archiving ($CONFIGURATION)"
xcodebuild archive \
  -project OffiCraft.xcodeproj \
  -scheme OffiCraft \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  | tail -40

APP="$ARCHIVE/Products/Applications/OffiCraft.app"
if [ ! -d "$APP" ]; then
  echo "error: archive produced no app at $APP" >&2
  exit 1
fi

echo "==> packaging"
PAYLOAD="$BUILD_DIR/Payload"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"

( cd "$BUILD_DIR" && zip -qry "$DIST_DIR/OffiCraft.ipa" Payload )

echo
echo "wrote $DIST_DIR/OffiCraft.ipa"
ls -lh "$DIST_DIR/OffiCraft.ipa"
echo
echo "This build is unsigned. To install on a device, resign it with your own"
echo "certificate and a profile covering link.hardcore.officraft and"
echo "link.hardcore.officraft.widgets."
