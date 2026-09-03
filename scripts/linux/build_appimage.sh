#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUNDLE_DIR=""
OUTPUT_DIR=""
VERSION=""
APPIMAGETOOL_BIN="${APPIMAGETOOL_BIN:-appimagetool}"
APP_NAME="Volward"
APP_ID="volward"
ICON_SOURCE="$REPO_ROOT/apps/volward/linux/icons/volward.png"
HICOLOR_SOURCE="$REPO_ROOT/apps/volward/linux/icons/hicolor"

usage() {
  cat <<'EOF'
Usage: build_appimage.sh --bundle-dir PATH --output-dir PATH --version X.Y.Z[+N]

Options:
  --bundle-dir   Flutter Linux bundle directory (contains volward, lib/, data/)
  --output-dir   Directory for the generated AppImage
  --version      App version from pubspec.yaml
  --appimagetool Path to appimagetool binary or AppImage
  --icon-source  SVG/PNG icon to embed in the AppDir root
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-dir)
      BUNDLE_DIR="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --appimagetool)
      APPIMAGETOOL_BIN="${2:-}"
      shift 2
      ;;
    --icon-source)
      ICON_SOURCE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$BUNDLE_DIR" || -z "$OUTPUT_DIR" || -z "$VERSION" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "❌ AppImage build failed: bundle directory not found: $BUNDLE_DIR" >&2
  exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "❌ AppImage build failed: icon source not found: $ICON_SOURCE" >&2
  exit 1
fi

if [[ ! -x "$APPIMAGETOOL_BIN" ]]; then
  APPIMAGETOOL_BIN="$(command -v "$APPIMAGETOOL_BIN" 2>/dev/null || true)"
fi

if [[ -z "$APPIMAGETOOL_BIN" || ! -x "$APPIMAGETOOL_BIN" ]]; then
  echo "❌ AppImage build failed: appimagetool not found" >&2
  echo "Set APPIMAGETOOL_BIN or install appimagetool first." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

APP_VERSION="${VERSION%%+*}"
APPIMAGE_NAME="Volward-v${APP_VERSION}-linux-x86_64.AppImage"
APPDIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_ID}.appdir.XXXXXX")"
cleanup() {
  rm -rf "$APPDIR"
}
trap cleanup EXIT

cp -a "$BUNDLE_DIR/." "$APPDIR/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
set -eu
APPDIR="${APPDIR:-$(dirname "$(readlink -f "$0")")}"
cd "$APPDIR"
export LD_LIBRARY_PATH="$APPDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$APPDIR/volward" "$@"
EOF
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/${APP_ID}.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Volward
Exec=volward
Icon=volward
StartupWMClass=com.volward.volward
Categories=Utility;
Terminal=false
EOF

# AppImage desktop Icon=volward expects a raster icon in AppDir root (+ .DirIcon).
case "$ICON_SOURCE" in
  *.png|*.PNG)
    cp "$ICON_SOURCE" "$APPDIR/volward.png"
    cp "$ICON_SOURCE" "$APPDIR/.DirIcon"
    ;;
  *)
    echo "❌ AppImage build failed: icon must be PNG (got: $ICON_SOURCE)" >&2
    exit 1
    ;;
esac

if [[ ! -d "$HICOLOR_SOURCE" ]]; then
  echo "❌ AppImage build failed: hicolor icons not found: $HICOLOR_SOURCE" >&2
  exit 1
fi
mkdir -p "$APPDIR/usr/share/icons"
cp -a "$HICOLOR_SOURCE" "$APPDIR/usr/share/icons/hicolor"

echo "🧱 Building AppImage: $APPIMAGE_NAME"
# Prefer extract-and-run so CI hosts without usable FUSE still work.
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"
ARCH=x86_64 VERSION="$APP_VERSION" "$APPIMAGETOOL_BIN" "$APPDIR" "$OUTPUT_DIR/$APPIMAGE_NAME"
echo "✅ AppImage build complete: $OUTPUT_DIR/$APPIMAGE_NAME"
