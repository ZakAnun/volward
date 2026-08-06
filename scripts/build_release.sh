#!/usr/bin/env bash
set -euo pipefail

# build_release.sh — Build release packages for macOS/Windows/Linux
# Usage: ./scripts/build_release.sh [--platform macos|windows|linux|all]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/volward"
BUILD_DIR="$REPO_ROOT/build/release"

PLATFORM="${1:-all}"

# Parse --platform flag
if [[ "$PLATFORM" == "--platform" ]]; then
  PLATFORM="${2:-all}"
fi

echo "🚀 Volward Release Builder"
echo "=========================="
echo "Platform: $PLATFORM"
echo ""

# Detect current OS
CURRENT_OS="unknown"
case "$(uname -s)" in
  Darwin*) CURRENT_OS="macos" ;;
  Linux*)  CURRENT_OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) CURRENT_OS="windows" ;;
esac

# Get version from pubspec.yaml
VERSION=$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed 's/version: //' | tr -d ' ')
echo "📦 Version: $VERSION"
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"

# Build Rust dylib first
build_rust() {
  echo "🦀 Building Rust dylib..."
  cd "$REPO_ROOT"
  cargo build --release -p volward-facade
  echo "✅ Rust build complete"
  echo ""
}

# Build macOS
build_macos() {
  if [[ "$CURRENT_OS" != "macos" ]]; then
    echo "⚠️  Skipping macOS build (requires macOS host)"
    return
  fi

  echo "🍎 Building macOS app..."
  cd "$APP_DIR"

  # Clean previous build
  rm -rf build/macos

  # Build .app bundle
  fvm flutter build macos --release

  # Copy to build directory
  APP_BUNDLE="$APP_DIR/build/macos/Build/Products/Release/volward.app"
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ macOS build failed: $APP_BUNDLE not found"
    exit 1
  fi

  # Create DMG (simple zip for now, can use create-dmg later)
  ARCH=$(uname -m)
  if [[ "$ARCH" == "arm64" ]]; then
    OUTPUT_NAME="volward-v${VERSION}-macos-arm64.zip"
  else
    OUTPUT_NAME="volward-v${VERSION}-macos-x64.zip"
  fi

  cd "$APP_DIR/build/macos/Build/Products/Release"
  zip -r "$BUILD_DIR/$OUTPUT_NAME" volward.app

  echo "✅ macOS build complete: $OUTPUT_NAME"
  echo ""
}

# Build Windows
build_windows() {
  if [[ "$CURRENT_OS" != "windows" ]]; then
    echo "⚠️  Skipping Windows build (requires Windows host)"
    return
  fi

  echo "🪟 Building Windows app..."
  cd "$APP_DIR"

  # Clean previous build
  rm -rf build/windows

  # Build
  flutter build windows --release

  # Copy to build directory
  WIN_BUILD="$APP_DIR/build/windows/x64/runner/Release"
  if [[ ! -d "$WIN_BUILD" ]]; then
    echo "❌ Windows build failed: $WIN_BUILD not found"
    exit 1
  fi

  OUTPUT_NAME="volward-v${VERSION}-windows-x64.zip"
  cd "$WIN_BUILD"
  zip -r "$BUILD_DIR/$OUTPUT_NAME" .

  echo "✅ Windows build complete: $OUTPUT_NAME"
  echo ""
}

# Build Linux
build_linux() {
  if [[ "$CURRENT_OS" != "linux" ]]; then
    echo "⚠️  Skipping Linux build (requires Linux host)"
    return
  fi

  echo "🐧 Building Linux app..."
  cd "$APP_DIR"

  # Clean previous build
  rm -rf build/linux

  # Build
  flutter build linux --release

  # Create tarball
  LINUX_BUILD="$APP_DIR/build/linux/x64/release/bundle"
  if [[ ! -d "$LINUX_BUILD" ]]; then
    echo "❌ Linux build failed: $LINUX_BUILD not found"
    exit 1
  fi

  OUTPUT_NAME="volward-v${VERSION}-linux-x64.tar.gz"
  cd "$(dirname "$LINUX_BUILD")"
  tar -czf "$BUILD_DIR/$OUTPUT_NAME" bundle

  echo "✅ Linux build complete: $OUTPUT_NAME"
  echo ""
}

# Main build flow
main() {
  # Always build Rust first
  build_rust

  case "$PLATFORM" in
    macos)
      build_macos
      ;;
    windows)
      build_windows
      ;;
    linux)
      build_linux
      ;;
    all)
      build_macos
      build_windows
      build_linux
      ;;
    *)
      echo "❌ Unknown platform: $PLATFORM"
      echo "Usage: $0 [--platform macos|windows|linux|all]"
      exit 1
      ;;
  esac

  echo "🎉 Build complete!"
  echo "📂 Output directory: $BUILD_DIR"
  echo ""
  ls -lh "$BUILD_DIR" || true
}

main
