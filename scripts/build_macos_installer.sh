#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Kamran ledger"
APP_SLUG="kamran-ledger"
VERSION="$(sed -n 's/^version: \(.*\)+[0-9][0-9]*$/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"

if [[ -z "${VERSION}" ]]; then
  VERSION="1.0.0"
fi

BUILD_DIR="$ROOT_DIR/build/macos/Build/Products/Release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
PKG_PATH="$DIST_DIR/${APP_SLUG}-${VERSION}-macos.pkg"

echo "Building macOS release app..."
cd "$ROOT_DIR"
flutter build macos --release

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release app not found at: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$PKG_PATH"

echo "Creating installer package..."
pkgbuild \
  --component "$APP_PATH" \
  --install-location /Applications \
  "$PKG_PATH"

echo
echo "Installer created:"
echo "  $PKG_PATH"
echo
echo "Note: this package is unsigned. On another Mac, Gatekeeper may warn"
echo "that the installer or app is from an unidentified developer."
