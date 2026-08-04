# Volward Logo

Volward is a macOS storage steward: it scans disk usage progressively, classifies files, keeps Finder-like navigation responsive, and moves selected reclaimable items to Trash. The logo keeps that shape direct, but as small and restrained as possible:

- The central **V** is both the Volward initial and a pair of scan beams converging on storage.
- The lower tray represents the scanned directory/catalog layer.
- The green sweep marks reclaimable space without making the logo a literal trash can.
- The palette follows the app tokens: Apple blue `#0066CC`, scan cyan `#5AC8FA`, and reclaim green `#34C759`.
- The live Flutter app uses a theme-aware `VolwardLogoMark` widget, so the mark can adapt to light/dark system theme.

## Files

| File | Use |
| --- | --- |
| `volward-logo.svg` | Primary square logo source, suitable for app icon exports. |
| `volward-logo.png` | 1024px PNG preview/export. |
| `volward-logo-128.png` | Small-size readability check. |
| `volward-wordmark.svg` | Minimal horizontal lockup for light backgrounds. |
| `volward-wordmark.png` | Transparent PNG export. |
| `volward-wordmark-preview.png` | White-background preview PNG. |
| `../lib/widgets/volward_logo.dart` | Theme-aware Flutter logo widget used in the app UI. |
| `../macos/Runner/Assets.xcassets/AppIcon.appiconset/` | macOS Dock / Finder app icons generated from `volward-logo.svg`. |

## Export

```bash
rsvg-convert -w 1024 -h 1024 apps/volward/branding/volward-logo.svg -o apps/volward/branding/volward-logo.png
rsvg-convert -w 128 -h 128 apps/volward/branding/volward-logo.svg -o apps/volward/branding/volward-logo-128.png
rsvg-convert -w 1480 -h 520 apps/volward/branding/volward-wordmark.svg -o apps/volward/branding/volward-wordmark.png
rsvg-convert -b white -w 1480 -h 520 apps/volward/branding/volward-wordmark.svg -o apps/volward/branding/volward-wordmark-preview.png

# macOS AppIcon sizes
ICON_DIR=apps/volward/macos/Runner/Assets.xcassets/AppIcon.appiconset
for s in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$s" -h "$s" apps/volward/branding/volward-logo.svg -o "$ICON_DIR/app_icon_$s.png"
done
```
