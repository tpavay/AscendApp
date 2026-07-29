# App Store screenshot sources

The two transformation photographs were generated specifically for Ascend with the built-in OpenAI image generator.
The raw photographs contain no text, logos, phones, or app interface; the renderer composites a real Ascend app surface onto each one.

All app imagery, including the insets on the transformation screens, is real Ascend app imagery already tracked in the repository:

- Screen 01 inset, live race: `web/public/images/ascend-live-climb-leaderboard-preview.png`
- Screen 02 inset, home: `web/public/images/ascend-home-live-climb.jpg`
- Screen 03, browse: `web/public/images/ascend-globe-browse.jpg`
- Screen 04, live race: `web/public/images/ascend-live-climb-leaderboard-preview.png`
- Screen 05, climb results: `web/public/images/ascend-live-climb-results.png`
- Screen 06, First Ascent: `web/public/images/ascend-climb-leaderboard.jpg` with the real `FirstAscentBadgeDetailed` app asset
- Screen 07, Best Efforts: `web/public/images/ascend-best-effort-detail.png`

No screen uses `web/public/images/ascend-climb-detail.jpg`.
It is the one capture whose Start Live Climb button is in its disabled state, and a storefront screenshot must not feature an inactive primary action.
The renderer still reads that file's status bar for the device-point measurements behind `statusBarSvg`.

`device-frame.png` is the frame supplied by the `aso-appstore-screenshots` skill.

Run the renderer from the repository root after installing the website dependencies:

```bash
npm --prefix web ci
node data/ascend-support-page-and-product-page-package/render-screenshots.mjs
```
