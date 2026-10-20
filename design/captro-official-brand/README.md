# Captro brand asset package

Production vector reconstruction of the selected first concept: two ascending, rounded curved strokes, the upper stroke shorter than the lower one. The same two closed Bézier paths are reused throughout every symbol, lockup, icon, and avatar. No raster concept image is embedded in the SVG masters.

## Start here

- `captro-brand-preview.png`: visual overview, not an app icon.
- `AppIcon.appiconset/`: ready-to-integrate conventional flat iOS asset catalog, default white symbol on black.
- `app-icons/captro-app-icon-dark-1024.png`: primary App Store/iOS source, 1024 × 1024, opaque RGB PNG.
- `app-icons/captro-app-icon-light-1024.png`: optional opposite colorway. Not automatically assigned to an appearance.
- `svg/`: transparent black/white symbols and horizontal lockups, with outlined lettering.
- `png/`: transparent high-resolution symbols (2048 px wide) and lockups (2400 px wide).
- `web/`: SVG favicon, multi-resolution ICO, 16/32/48/64 PNG favicons, 180 px Apple touch icon, and 192/512 px web icons plus a manifest.
- `social/`: 512 × 512 opaque square avatars, dark and light.
- `source/`: reproducible vector-building script and original licensed font.
- `licenses/`: font license and attribution.
- `validation.json`: dimensions, color modes, alpha inventory, and checks.

## Xcode / Codex handoff

See `CODEX-HANDOFF.md` for a copyable implementation brief. Integration is not already performed: this package contains assets only. No project, account, store listing, upload, or release was modified.

1. Inspect the app target's existing asset catalog and icon settings before making changes.
2. Integrate `AppIcon.appiconset` into the intended asset catalog. If an AppIcon set already exists, update its contents carefully instead of creating a duplicate or overwriting unrelated assets.
3. The included Contents.json uses the single-size universal iOS 1024 × 1024 format. Confirm the project's Xcode version and target support this format. Preserve older required slots if the project uses them; generate any required legacy sizes from the 1024 master rather than enlarging a smaller icon.
4. Set or preserve the target's app icon name as the chosen asset set. Build and inspect the icon in the simulator or on device. Do not change app UI, navigation, colors, typography, layout, or other branding without a separate request.
5. Keep the PNG square and opaque. Do not bake rounded corners or transparent corners into it. Apple applies the platform mask.
6. No App Store submission, release, external upload, account change, or signing change is authorized by this package. Ask for that separately.

This is a conventional flat app-icon asset, not an Icon Composer layered asset. The light export is an optional alternative, not a promised automatic dark/light or tinted implementation.

Apple references:
- https://developer.apple.com/documentation/xcode/configuring-your-app-icon
- https://developer.apple.com/design/human-interface-guidelines/app-icons

## Design usage

Colors are pure black (#000000) and white (#FFFFFF). Use black on a light background and white on a dark background. Preserve proportions and the space between the strokes. Do not rotate, stretch, add gradients, add outlines, or recreate the mark from text characters.

Keep at least one stroke thickness of clear space around the visible mark in ordinary branding. App icons use the supplied balanced square composition. Use the symbol without lettering at tiny sizes. The small favicon exports use the same mark geometry rather than a different logo.

The wordmark uses Poppins Medium, converted to editable outlines. It is a deliberate production match to the clean geometric character of the concept, not an assertion that the AI-generated reference lettering has been exactly identified. The reference symbol has been reconstructed and smoothed as native vector contours, not mathematically traced pixel-for-pixel.

White transparent artwork can appear blank against a white viewer; inspect it on a dark background. SVG viewBoxes include intentional clear space.

## Licensing and scope

Poppins is by the Indian Type Foundry and is distributed under the SIL Open Font License 1.1. The unmodified font and full supplied license are included. See `licenses/ATTRIBUTION.md` for source URLs and details. Font software licensing does not establish trademark availability of the Captro name or logo. No trademark search, registration, legal clearance, exclusivity warranty, or App Store approval is implied.

## Rebuild

Requires Python 3 with Pillow and fontTools, plus Inkscape on PATH. Run `python source/build_assets.py` from any working directory. The script builds files relative to its own directory and never modifies an app repository. All wordmark export lettering is outlined; no end-user font installation is needed to use the SVG or PNG assets.
