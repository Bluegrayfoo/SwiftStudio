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

mkdir -p "$WORK_DIR/src" "$INSTALL_DIR"

if [[ -f "$SCRIPT_DIR/src/preview_runner_native.m" ]]; then
  cp "$SCRIPT_DIR/src/preview_runner_native.m" "$WORK_DIR/src/preview_runner_native.m"
else
  curl -fsSL "$REPO_RAW/src/preview_runner_native.m" -o "$WORK_DIR/src/preview_runner_native.m"
fi

clang -fobjc-arc -framework AppKit "$WORK_DIR/src/preview_runner_native.m" -o "$INSTALL_DIR/preview_runner"
chmod +x "$INSTALL_DIR/preview_runner"

echo "Installed SwiftStudio preview runner app:"
echo "  $INSTALL_DIR/preview_runner"
echo
echo "Run:"
echo "  $INSTALL_DIR/preview_runner --all"
