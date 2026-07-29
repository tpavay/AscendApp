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

The two approved transformation photographs are preserved in `sources/`.
They are used as full-bleed backgrounds rather than replaced.

Every screen contains genuine Ascend UI.
Screen 01 uses the real Live Climb share capture.
Screen 02 uses a Simulator capture of Ascend's landmark onboarding surface, including its Everest card.
Screens 03 through 05 use the real globe, live replay leaderboard, and per-climb leaderboard captures.
Screen 06 uses a Simulator capture of Ascend's First Ascent notification surface with its genuinely enabled primary action.
Screen 07 uses the real Best Effort detail capture.

The renderer reuses one status-bar master on all seven screens.
That master supplies the same 9:41 clock, full signal, full Wi-Fi, full battery, and correctly placed Dynamic Island pill.
The app body begins below the normalized status band at a complete UI boundary.

## Render

Install the website dependencies, then run the renderer from the repository root:

```bash
npm --prefix web ci
node AppStoreAssets/render-screenshots.mjs
```

The renderer validates the exact file count, dimensions, sRGB color space, and absence of alpha before writing the contact sheet.
