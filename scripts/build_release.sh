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

# Get version from pubspec.yaml (strip +build for artifact filenames)
VERSION_RAW=$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed 's/version: //' | tr -d ' ')
VERSION="${VERSION_RAW%%+*}"
echo "📦 Version: $VERSION (from $VERSION_RAW)"
echo ""

if [[ -z "${VOLWARD_API_BASE:-}" ]]; then
  if [[ "${ALLOW_UNCONFIGURED_PLATFORM:-}" == "1" ]]; then
    VOLWARD_API_BASE=""
  else
    echo "❌ VOLWARD_API_BASE is required for release builds"
    echo "Set it to the deployed Platform API base, for example https://api.example.com/v1."
    echo "Use ALLOW_UNCONFIGURED_PLATFORM=1 only for local experiments."
    exit 1
  fi
fi
VOLWARD_DEFINE_ARGS=(--dart-define="VOLWARD_API_BASE=$VOLWARD_API_BASE")

# Create build directory
mkdir -p "$BUILD_DIR"

write_sha256() {
  local file="$1"
  local dir
  local name
  dir="$(dirname "$file")"
  name="$(basename "$file")"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$dir" && sha256sum "$name" > "$name.sha256")
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$dir" && shasum -a 256 "$name" > "$name.sha256")
  else
    echo "❌ SHA-256 checksum tool not found" >&2
    exit 1
  fi
}

# Aptabase compile-time defines for release builds.
# Priority: env APTABASE_APP_KEY + APTABASE_HOST → apps/volward/aptabase.json
# Release builds require Aptabase so Windows/Linux packages cannot ship as silent Noop.
# Escape hatch for local experiments: ALLOW_NOOP_ANALYTICS=1
# shellcheck source=../apps/volward/scripts/resolve_aptabase_defines.sh
source "$APP_DIR/scripts/resolve_aptabase_defines.sh"
if [[ "${ALLOW_NOOP_ANALYTICS:-}" == "1" ]]; then
  resolve_aptabase_defines || true
else
  resolve_aptabase_defines --require
fi
echo ""

to_windows_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$path"
  else
    printf '%s\n' "$path"
  fi
}

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

  # Build .app bundle (Xcode Run Script phase invokes macos/build_rust.sh)
  fvm flutter build macos --release \
    "${APTABASE_DEFINE_ARGS[@]}" "${VOLWARD_DEFINE_ARGS[@]}"

  # Copy to build directory
  APP_BUNDLE="$APP_DIR/build/macos/Build/Products/Release/volward.app"
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ macOS build failed: $APP_BUNDLE not found"
    exit 1
  fi
  if [[ ! -x "$APP_BUNDLE/Contents/MacOS/volward" ]]; then
    echo "❌ macOS build failed: executable missing in app bundle"
    exit 1
  fi
  if [[ ! -f "$APP_BUNDLE/Contents/Frameworks/libvolward_facade.dylib" ]]; then
    echo "❌ macOS build failed: libvolward_facade.dylib missing in Frameworks"
    exit 1
  fi

  # Create zip archive (DMG can replace this later)
  ARCH=$(uname -m)
  if [[ "$ARCH" == "arm64" ]]; then
    OUTPUT_NAME="volward-v${VERSION}-macos-arm64.zip"
  else
    OUTPUT_NAME="volward-v${VERSION}-macos-x64.zip"
  fi

  cd "$APP_DIR/build/macos/Build/Products/Release"
  # Avoid AppleDouble (._*) junk inside the zip.
  COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent volward.app "$BUILD_DIR/$OUTPUT_NAME"
  write_sha256 "$BUILD_DIR/$OUTPUT_NAME"

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

  # Build (same Aptabase defines as macOS/Linux — required unless ALLOW_NOOP_ANALYTICS=1)
  if command -v fvm >/dev/null 2>&1; then
    fvm flutter build windows --release \
      "${APTABASE_DEFINE_ARGS[@]}" "${VOLWARD_DEFINE_ARGS[@]}"
  else
    flutter build windows --release \
      "${APTABASE_DEFINE_ARGS[@]}" "${VOLWARD_DEFINE_ARGS[@]}"
  fi

  # Copy to build directory
  WIN_BUILD="$APP_DIR/build/windows/x64/runner/Release"
  if [[ ! -d "$WIN_BUILD" ]]; then
    echo "❌ Windows build failed: $WIN_BUILD not found"
    exit 1
  fi

  if [[ ! -f "$REPO_ROOT/target/release/volward_facade.dll" ]]; then
    echo "❌ Windows build failed: target/release/volward_facade.dll not found"
    exit 1
  fi

  cp -f "$REPO_ROOT/target/release/volward_facade.dll" "$WIN_BUILD/volward_facade.dll"

  if ! command -v iscc >/dev/null 2>&1; then
    echo "❌ Windows installer build failed: Inno Setup compiler (iscc) not found"
    echo "Install Inno Setup, then re-run this script."
    exit 1
  fi

  ISCC_SOURCE_DIR="$(to_windows_path "$WIN_BUILD")"
  ISCC_OUTPUT_DIR="$(to_windows_path "$BUILD_DIR")"
  ISCC_ICON_FILE="$(to_windows_path "$APP_DIR/windows/runner/resources/app_icon.ico")"
  ISCC_SCRIPT="$(to_windows_path "$REPO_ROOT/scripts/windows/volward.iss")"
  iscc \
    "/DAppVersion=$VERSION" \
    "/DSourceDir=$ISCC_SOURCE_DIR" \
    "/DOutputDir=$ISCC_OUTPUT_DIR" \
    "/DIconFile=$ISCC_ICON_FILE" \
    "$ISCC_SCRIPT"

  if [[ ! -f "$BUILD_DIR/VolwardSetup-v${VERSION}-windows-x64.exe" ]]; then
    echo "❌ Windows installer missing: VolwardSetup-v${VERSION}-windows-x64.exe"
    exit 1
  fi
  write_sha256 "$BUILD_DIR/VolwardSetup-v${VERSION}-windows-x64.exe"

  echo "✅ Windows build complete: VolwardSetup-v${VERSION}-windows-x64.exe"
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

  # Build (same Aptabase defines as macOS/Windows — required unless ALLOW_NOOP_ANALYTICS=1)
  if command -v fvm >/dev/null 2>&1; then
    fvm flutter build linux --release \
      "${APTABASE_DEFINE_ARGS[@]}" "${VOLWARD_DEFINE_ARGS[@]}"
  else
    flutter build linux --release \
      "${APTABASE_DEFINE_ARGS[@]}" "${VOLWARD_DEFINE_ARGS[@]}"
  fi

  # Create tarball
  LINUX_BUILD="$APP_DIR/build/linux/x64/release/bundle"
  if [[ ! -d "$LINUX_BUILD" ]]; then
    echo "❌ Linux build failed: $LINUX_BUILD not found"
    exit 1
  fi

  if [[ ! -f "$REPO_ROOT/target/release/libvolward_facade.so" ]]; then
    echo "❌ Linux build failed: target/release/libvolward_facade.so not found"
    exit 1
  fi

  mkdir -p "$LINUX_BUILD/lib"
  cp -f "$REPO_ROOT/target/release/libvolward_facade.so" "$LINUX_BUILD/lib/libvolward_facade.so"

  OUTPUT_NAME="volward-v${VERSION}-linux-x64.tar.gz"
  cd "$(dirname "$LINUX_BUILD")"
  tar -czf "$BUILD_DIR/$OUTPUT_NAME" bundle
  write_sha256 "$BUILD_DIR/$OUTPUT_NAME"

  bash "$REPO_ROOT/scripts/linux/build_appimage.sh" \
    --bundle-dir "$LINUX_BUILD" \
    --output-dir "$BUILD_DIR" \
    --version "$VERSION" \
    --icon-source "$REPO_ROOT/apps/volward/branding/volward-logo.png"

  if [[ ! -f "$BUILD_DIR/Volward-v${VERSION}-linux-x86_64.AppImage" ]]; then
    echo "❌ Linux AppImage missing: Volward-v${VERSION}-linux-x86_64.AppImage"
    exit 1
  fi
  write_sha256 "$BUILD_DIR/Volward-v${VERSION}-linux-x86_64.AppImage"

  echo "✅ Linux build complete: $OUTPUT_NAME and Volward-v${VERSION}-linux-x86_64.AppImage"
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
