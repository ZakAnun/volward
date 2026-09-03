#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SVG="$ROOT/apps/volward/branding/volward-logo.svg"
MAC="$ROOT/apps/volward/macos/Runner/Assets.xcassets/AppIcon.appiconset"
WIN="$ROOT/apps/volward/windows/runner/resources"
LINUX="$ROOT/apps/volward/linux/icons"

if ! command -v rsvg-convert >/dev/null; then
  echo "rsvg-convert is required (librsvg)" >&2
  exit 1
fi

for s in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$s" -h "$s" "$SVG" -o "$MAC/app_icon_$s.png"
done

mkdir -p "$LINUX"
for s in 16 32 48 64 128 256 512; do
  dest="$LINUX/hicolor/${s}x${s}/apps"
  mkdir -p "$dest"
  rsvg-convert -w "$s" -h "$s" "$SVG" -o "$dest/volward.png"
done
cp "$LINUX/hicolor/512x512/apps/volward.png" "$LINUX/volward.png"

TMP="$(mktemp -d)"
for s in 16 32 48 256; do
  rsvg-convert -w "$s" -h "$s" "$SVG" -o "$TMP/$s.png"
done
if command -v magick >/dev/null; then
  magick "$TMP/16.png" "$TMP/32.png" "$TMP/48.png" "$TMP/256.png" "$WIN/app_icon.ico"
elif command -v convert >/dev/null; then
  convert "$TMP/16.png" "$TMP/32.png" "$TMP/48.png" "$TMP/256.png" "$WIN/app_icon.ico"
else
  echo "ImageMagick (magick/convert) is required to write app_icon.ico" >&2
  exit 1
fi
rm -rf "$TMP"
echo "Exported Volward icons"
