#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${SWIFTSTUDIO_INSTALL_DIR:-$HOME/cmds}"
REPO_RAW="${SWIFTSTUDIO_REPO_RAW:-https://raw.githubusercontent.com/Bluegrayfoo/SwiftStudio/main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR/src" "$WORK_DIR/assets" "$INSTALL_DIR"

if [[ -f "$SCRIPT_DIR/src/code_studio_native.m" ]]; then
  cp "$SCRIPT_DIR/src/code_studio_native.m" "$WORK_DIR/src/code_studio_native.m"
  cp "$SCRIPT_DIR/assets/swiftlogo.png" "$WORK_DIR/assets/swiftlogo.png"
  cp "$SCRIPT_DIR/assets/nssp_icon.png" "$WORK_DIR/assets/nssp_icon.png"
  cp "$SCRIPT_DIR/assets/ss_logo.png" "$WORK_DIR/assets/ss_logo.png"
  cp "$SCRIPT_DIR/README.md" "$WORK_DIR/README.md"
else
  curl -fsSL "$REPO_RAW/src/code_studio_native.m" -o "$WORK_DIR/src/code_studio_native.m"
  curl -fsSL "$REPO_RAW/assets/swiftlogo.png" -o "$WORK_DIR/assets/swiftlogo.png"
  curl -fsSL "$REPO_RAW/assets/nssp_icon.png" -o "$WORK_DIR/assets/nssp_icon.png"
  curl -fsSL "$REPO_RAW/assets/ss_logo.png" -o "$WORK_DIR/assets/ss_logo.png"
  curl -fsSL "$REPO_RAW/README.md" -o "$WORK_DIR/README.md"
fi

SOURCE="$WORK_DIR/src/code_studio_native.m"
LOGO="$WORK_DIR/assets/swiftlogo.png"
NSSP_ICON="$WORK_DIR/assets/nssp_icon.png"
SS_LOGO="$WORK_DIR/assets/ss_logo.png"
README="$WORK_DIR/README.md"

clang -fobjc-arc -framework AppKit "$SOURCE" -o "$INSTALL_DIR/code_studio"

cp "$LOGO" "$INSTALL_DIR/swiftlogo.png"
cp "$NSSP_ICON" "$INSTALL_DIR/nssp_icon.png"
cp "$SS_LOGO" "$INSTALL_DIR/ss_logo.png"
cp "$README" "$INSTALL_DIR/README_SwiftStudio.md"

chmod +x "$INSTALL_DIR/code_studio"

echo "Installed SwiftStudio command:"
echo "  $INSTALL_DIR/code_studio"
echo
if [[ "${SWIFTSTUDIO_NO_LAUNCH:-0}" == "1" ]]; then
  echo "Run:"
  echo "  $INSTALL_DIR/code_studio --thread Thread1"
else
  echo "Opening SwiftStudio..."
  "$INSTALL_DIR/code_studio" --thread Thread1 >/dev/null 2>&1 &
fi
