#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${SWIFTSTUDIO_INSTALL_DIR:-$HOME/cmds}"
REPO_RAW="${SWIFTSTUDIO_REPO_RAW:-https://raw.githubusercontent.com/Bluegrayfoo/SwiftStudio/main}"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR/src" "$WORK_DIR/assets" "$INSTALL_DIR"

curl -fsSL "$REPO_RAW/src/code_studio_native.m" -o "$WORK_DIR/src/code_studio_native.m"
curl -fsSL "$REPO_RAW/assets/swiftlogo.png" -o "$WORK_DIR/assets/swiftlogo.png"
curl -fsSL "$REPO_RAW/README.md" -o "$WORK_DIR/README.md"

SOURCE="$WORK_DIR/src/code_studio_native.m"
LOGO="$WORK_DIR/assets/swiftlogo.png"
README="$WORK_DIR/README.md"

clang -fobjc-arc -framework AppKit "$SOURCE" -o "$INSTALL_DIR/code_studio"

cp "$LOGO" "$INSTALL_DIR/swiftlogo.png"
cp "$README" "$INSTALL_DIR/README_SwiftStudio.md"

chmod +x "$INSTALL_DIR/code_studio"

echo "Installed SwiftStudio command:"
echo "  $INSTALL_DIR/code_studio"
echo
echo "Run:"
echo "  $INSTALL_DIR/code_studio --thread Thread1"
