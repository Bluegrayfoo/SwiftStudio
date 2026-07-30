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

mkdir -p "$WORK_DIR/src" "$WORK_DIR/fishy_syntax/Sources/FishySyntax" "$INSTALL_DIR"

if [[ -f "$SCRIPT_DIR/src/preview_runner_native.m" ]]; then
  cp "$SCRIPT_DIR/src/preview_runner_native.m" "$WORK_DIR/src/preview_runner_native.m"
  if [[ -f "$SCRIPT_DIR/src/fishy_syntax/Sources/FishySyntax/main.swift" ]]; then
    cp "$SCRIPT_DIR/src/fishy_syntax/Sources/FishySyntax/main.swift" "$WORK_DIR/fishy_syntax/Sources/FishySyntax/main.swift"
  fi
else
  curl -fsSL "$REPO_RAW/src/preview_runner_native.m" -o "$WORK_DIR/src/preview_runner_native.m"
  curl -fsSL "$REPO_RAW/src/fishy_syntax/Sources/FishySyntax/main.swift" -o "$WORK_DIR/fishy_syntax/Sources/FishySyntax/main.swift" || true
fi

clang -fobjc-arc -framework AppKit "$WORK_DIR/src/preview_runner_native.m" -o "$INSTALL_DIR/preview_runner"
chmod +x "$INSTALL_DIR/preview_runner"

if [[ -f "$WORK_DIR/fishy_syntax/Sources/FishySyntax/main.swift" && -d "$HOME/fishytool/swift-syntax" ]]; then
  FISHY_CACHE_ROOT="$HOME/fishytool/fishy_syntax_helper"
  FISHY_PACKAGE_DIR="$FISHY_CACHE_ROOT/package"
  FISHY_BUILD_DIR="$FISHY_CACHE_ROOT/build"
  mkdir -p "$FISHY_PACKAGE_DIR/Sources/FishySyntax" "$FISHY_BUILD_DIR"
  cp "$WORK_DIR/fishy_syntax/Sources/FishySyntax/main.swift" "$FISHY_PACKAGE_DIR/Sources/FishySyntax/main.swift"
  cat > "$FISHY_PACKAGE_DIR/Package.swift" <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "FishySyntax",
  platforms: [.macOS(.v10_15)],
  products: [
    .executable(name: "fishy_syntax", targets: ["FishySyntax"])
  ],
  dependencies: [
    .package(path: "$HOME/fishytool/swift-syntax")
  ],
  targets: [
    .executableTarget(
      name: "FishySyntax",
      dependencies: [
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    )
  ]
)
EOF
  if [[ -x "$INSTALL_DIR/fishy_syntax" && "$INSTALL_DIR/fishy_syntax" -nt "$FISHY_PACKAGE_DIR/Sources/FishySyntax/main.swift" ]]; then
    :
  elif cd "$FISHY_PACKAGE_DIR" && CLANG_MODULE_CACHE_PATH="$FISHY_CACHE_ROOT/clang-module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$FISHY_CACHE_ROOT/swiftpm-module-cache" swift build --disable-sandbox -c release --product fishy_syntax --scratch-path "$FISHY_BUILD_DIR" >/dev/null 2>&1; then
    cp "$FISHY_BUILD_DIR/release/fishy_syntax" "$INSTALL_DIR/fishy_syntax"
    chmod +x "$INSTALL_DIR/fishy_syntax"
  else
    echo "Fishy SwiftSyntax helper was not installed; runner will use built-in suggestions."
  fi
fi

echo "Installed SwiftStudio preview runner app:"
echo "  $INSTALL_DIR/preview_runner"
if [[ -x "$INSTALL_DIR/fishy_syntax" ]]; then
  echo "Installed Fishy SwiftSyntax helper:"
  echo "  $INSTALL_DIR/fishy_syntax"
fi
echo
echo "Run:"
echo "  $INSTALL_DIR/preview_runner --all"
