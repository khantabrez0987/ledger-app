#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_PATH="$(find "$ROOT_DIR/dist" -maxdepth 1 -name '*-macos.pkg' | head -n 1 || true)"

if [[ -z "${PKG_PATH:-}" || ! -f "$PKG_PATH" ]]; then
  echo "Installer package not found. Building package now..."
  "$ROOT_DIR/scripts/build_macos_installer.sh"
  PKG_PATH="$(find "$ROOT_DIR/dist" -maxdepth 1 -name '*-macos.pkg' | head -n 1 || true)"
fi

if [[ -z "${PKG_PATH:-}" || ! -f "$PKG_PATH" ]]; then
  osascript -e 'display alert "Installer not found" message "Unable to build the installer package. Please open Terminal and run scripts/build_macos_installer.sh."'
  exit 1
fi

open "$PKG_PATH"
