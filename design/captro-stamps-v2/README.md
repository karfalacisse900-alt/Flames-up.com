# Captro Stamp Kit · V2

Fifteen original editable vector designs for **Moment, Club, Event, Meetup and Deal**. Each design has a full layout and a separately arranged compact layout. This kit replaces the earlier stamp artwork; it does not change your live app.

## Open the designs

Open `studio.html` in a browser. Choose a stamp, edit its text and export an editable SVG, a transparent 4× PNG, a blank frame or the stamp's app-data JSON. The studio is self-contained and makes no network requests. Changes remain in the preview until the page is refreshed; export your edits to keep them. A managed browser can restrict local HTML files; the same folder can be served with your usual local development server.

`preview/all-15-stamps.png` shows all full designs. `preview/all-15-compact.png` shows their feed layouts. Both are overview images, not app assets.

## What changed

- Reworked type sizes, baselines and spacing; changed the reference typography to Inter and EB Garamond with system fallbacks.
- Stronger ink/paper contrast and a more deliberate mix of light and dark printed stamps.
- Cleaner contours, actual transparent tag holes and ticket notches, subtle vector paper marks and thin paper-edge shading.
- Compact layouts remove secondary lines instead of shrinking an entire full layout. One 232px-wide compact stamp is 81.2px tall.
- Reference lettering is also supplied as vector outlines, so the supplied static examples can retain their appearance without a font dependency.
- 2560px-wide transparent PNGs, updated TypeScript rendering code and an offline studio with individual SVG/PNG/data exports.

## Contents

| Folder / file | Purpose |
|---|---|
| `assets/svg/` | 15 full SVGs with editable text. |
| `assets/svg-compact/` | 15 compact SVGs with editable text. |
| `assets/frames/`, `assets/frames-compact/` | 30 blank vector frames. |
| `assets/outlined/`, `assets/outlined-compact/` | 30 fixed-lettering vector reference assets. Text is converted to shapes in these files only. |
| `assets/png-4x/` | 15 transparent 2560 × 1152px reference PNGs. |
| `assets/png-compact-4x/` | 15 transparent 2560 × 896px reference PNGs. |
| `src/` | Typed data model, vector geometry, renderer, web/native wrappers and examples. |
| `dist/` | Compiled pure-renderer JavaScript and type declarations. |
| `studio.html` | Standalone editable design studio. |
| `examples.json`, `tokens.json`, `manifest.json` | Example data, design settings and asset paths. |
| `CODEX_HANDOFF.md` | Implementation instructions and release checks. |
| `tests/` | Automated checks and recorded results. |

## Use in Captro

Give Codex this entire folder and ask it to read `CODEX_HANDOFF.md`. Keep the existing five stamp types. Variants are visual options, not new categories or navigation tabs.

Copy `src/` into the application's component area; do not replace the app's package configuration. Import the native or web component explicitly:

```tsx
import { CaptroStamp } from './captro-stamps/CaptroStamp.native';
// Web: import { CaptroStamp } from './captro-stamps/CaptroStamp.web';
import type { StampData } from './captro-stamps/types';

const stamp: StampData = {
  id: 'demo-deal',
  type: 'deal',
  variant: 'deal-cashback',
  title: '$4 BACK',
  meta: 'JOE’S PIZZA',
  footer: 'SPEND $20+ · SCAN RECEIPT',
  compactText: 'JOE’S PIZZA · $20 MIN.',
};

export function PostStamp({ openDetails }: {
  openDetails: (data: StampData) => void;
}) {
  return <CaptroStamp data={stamp} density="compact" width={232}
    onPress={openDetails} />;
}
```

The native wrapper uses `react-native-svg`; in an Expo app, use its compatible version with `npx expo install react-native-svg`. The web wrapper uses the application's existing React installation. Neither wrapper performs purchases, admission, joining, reward verification or payouts.

## Typography and fidelity

No font files are distributed or embedded. The supplied editable examples reference **Inter** and **EB Garamond** with fallbacks. They were rendered using locally installed fonts. The native wrapper defaults to platform fonts (Helvetica Neue / Georgia on iOS; generic sans/serif on Android). Use the optional `fonts` prop to match fonts your app already has installed and licensed.

Consequently, dynamic text can look slightly different on another device. `outlined/` and `outlined-compact/` preserve the exact static reference lettering as ordinary vector paths; these are not editable live titles. Use the text renderer for live data, not outlined screenshots. Test the real app fonts and languages before release.

## Layout and migration from V1

The 15 variant identifiers and five types are preserved. The artwork proportions have changed:

- Full: `viewBox="0 0 640 288"`.
- Compact: `viewBox="0 0 640 224"`.

Both app wrappers default to compact, width 232 and optional paper marks off. Do not keep V1's hard-coded 640:264 ratio. Template definitions now expose `full` and `compact` layouts. The pure `renderStamp` function defaults to full for design exports.

Use one stamp over the media, approximately 12px inset. Preserve the existing photo/video ratios. Compact text is a short summary, never a substitute for offer terms or accessible detail text. Full labels retain the original record's content for assistive technology.

The native `onHide` callback is optional; the containing post must provide a way to restore a hidden stamp. The web wrapper intentionally exposes only the existing detail callback; add any hide/restore interaction in the containing media component. Do not hide stamps when users scroll.

## Validation and rebuilding

The core renderer type-checks and has 15 passing Node tests. Browser checks cover all 30 sample layouts, text bounds, text-to-text overlap, filters, editing, exports, injection handling and a 390px-wide viewport. These checks are not a substitute for app or device testing. See `VALIDATION.md`.

With TypeScript available in the development environment:

```sh
npm test
npm run export
python tools/build-studio.py
```

`tools/build-designs.py` is the source generator for layout geometry and examples. Editing `src/templates.ts` directly works, but rerunning the generator will replace those manual edits. For durable geometry changes, edit the generator. To regenerate PNGs and fixed-lettering examples, `python tools/outline-and-render.py` requires locally installed reference fonts, FontTools and CairoSVG. `tools/test-browser.py` additionally requires Playwright and Chromium. These are development tools, not mobile app dependencies.

## API references

Checked September 20, 2026. These references concern the wrappers, not the artwork:

- React SVG and HTML insertion: https://react.dev/reference/react-dom/components/common
- React Native SVG installation and usage: https://github.com/software-mansion/react-native-svg

All example clubs, memberships, events and offers are illustrative. No merchant participation, redemption eligibility or payment functionality is implied.
