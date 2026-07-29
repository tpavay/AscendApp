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

Every image input lives in `sources/`, so re-cropping or replacing a website marketing image cannot change these renders.
Nothing under `web/` is read as image input; the only thing this script takes from `web/` is the Sharp package - see Render below.

The two approved transformation photographs are preserved as `01-stair-stepper-effort.png` and `02-everest-summit.png`.
They are used as full-bleed backgrounds rather than replaced.

Every screen contains genuine Ascend UI, and every pixel inside every phone screen comes from one of these captures:

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
Every capture is a whole 19.5:9 iPhone screen, so the screen is 1012 x 2182 and each capture lands at its true proportions.
Scaling is always width-driven, which is what keeps app text, card edges and controls off the crop line.

Each screen declares the last capture row that must be whole and the first row that must not appear at all.
The body height was chosen so every screen's bottom edge lands in the gap between those two rows, and the renderer refuses to build a body that falls outside it.
`qa/review.md` tabulates the boundary chosen for each screen.

Screens 02 through 07 show the whole device inside the canvas.
Screen 01 runs its device off the bottom: the recap card is about half a screen tall and the capture has no further chrome-free surface below it, so a fully framed device could only have been completed with invented pixels. Bleeding it instead keeps the lead screenshot entirely real.

The renderer reuses one status-bar master on all seven screens.
That master supplies the same 9:41 clock, full signal, full Wi-Fi, full battery, and correctly placed Dynamic Island pill.

## Render

Sharp is resolved from `web/node_modules` through `web/package.json`, which is the repository's only declaration of it; there is no separate manifest here.
Install the website dependencies first, then run the renderer from anywhere:

```bash
npm --prefix web ci
node AppStoreAssets/render-screenshots.mjs
```

Every path other than that Sharp lookup is derived from the script's own location, so the working directory does not matter.

Before writing anything the renderer checks that each device fits between the headline rule and the bottom of the canvas, that each capture is tall enough to fill the screen without cropping sideways, and that no body's bottom edge slices a declared element.
After rendering it validates the exact file count, dimensions, sRGB color space, absence of alpha, and status-bar uniformity, then writes the contact sheet.
