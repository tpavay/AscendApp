# Ascend App Store screenshots

This directory contains the final en-US iPhone screenshot set and its reproducible renderer.

## Final deliverables

- Upload-ready screenshots: `screenshots/iphone-6.9-en-US/`
- Seven-screen contact sheet: `qa/app-store-contact-sheet.png`
- Renderer: `render-screenshots.mjs`

The upload directory contains exactly seven 1320 x 2868 PNG files.
Every output is sRGB and has no alpha channel.
The app target is iPhone-only, so there is no iPad set.

## Source integrity

Every input lives in `sources/`, so the package renders the same whatever else changes in the repository.
Nothing is read from `web/`.

The two approved transformation photographs are preserved as `01-stair-stepper-effort.png` and `02-everest-summit.png`.
They are used as full-bleed backgrounds rather than replaced.

Every screen contains genuine Ascend UI, taken whole:

| Screen | Capture |
|---|---|
| 01 | `real-ui-live-climb-share.png` - the Live Climb recap card, share workflow cropped away |
| 02 | `real-ui-landmarks.png` - landmark onboarding, including the Everest card |
| 03 | `real-ui-globe-browse.jpg` - the live globe and climb catalog |
| 04 | `real-ui-live-attempt-leaderboard.png` - an in-progress replay leaderboard |
| 05 | `real-ui-climb-leaderboard.jpg` - the per-climb completion leaderboard |
| 06 | `real-ui-first-ascent.png` - the First Ascent notification surface |
| 07 | `real-ui-best-effort.png` - a Best Effort record and its progression chart |

## Geometry

The phone screen is sized from the captures rather than the other way round.
Every capture is a whole 19.5:9 iPhone screen, so the inner screen is 1012 x 2192 and each capture lands at its true proportions.
Scaling is always width-driven, which is what keeps app text, card edges and controls off the crop line.

The whole device fits inside the canvas, so nothing is sliced by the canvas edge.
Where app content does meet the bottom of the phone screen it is the capture's own scroll edge, framed by the bezel, as the running app renders it.

The renderer reuses one status-bar master on all seven screens.
That master supplies the same 9:41 clock, full signal, full Wi-Fi, full battery, and correctly placed Dynamic Island pill.

Screen 01 is the one screen whose subject is smaller than a phone screen: the recap card is roughly half a screen tall.
Its body is the widest chrome-free window of the real capture, centred on the card, with that window's own edge tone continuing to the top and bottom of the screen.

## Render

Install the website dependencies, then run the renderer from anywhere:

```bash
npm --prefix web ci
node AppStoreAssets/render-screenshots.mjs
```

`sharp` is resolved from `web/node_modules`; every other path is derived from the script's own location.

Before writing anything the renderer checks that the phone frame fits inside the canvas, and it refuses to build a body from a capture too short to fill the screen without cropping sideways.
After rendering it validates the exact file count, dimensions, sRGB color space, absence of alpha, and status-bar uniformity, then writes the contact sheet.
