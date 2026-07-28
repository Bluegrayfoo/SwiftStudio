#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${SWIFTSTUDIO_INSTALL_DIR:-$HOME/cmds}"

mkdir -p "$INSTALL_DIR"

clang -fobjc-arc -framework AppKit "$ROOT/src/code_studio_native.m" -o "$INSTALL_DIR/code_studio"

cp "$ROOT/assets/swiftlogo.png" "$INSTALL_DIR/swiftlogo.png"
cp "$ROOT/README.md" "$INSTALL_DIR/README_SwiftStudio.md"

chmod +x "$INSTALL_DIR/code_studio"

echo "Installed SwiftStudio command:"
echo "  $INSTALL_DIR/code_studio"
echo
echo "Run:"
echo "  $INSTALL_DIR/code_studio --thread Thread1"