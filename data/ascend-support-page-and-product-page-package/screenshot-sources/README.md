# App Store screenshot sources

The two transformation photographs were generated specifically for Ascend with the built-in OpenAI image generator.
The raw photographs contain no text, logos, phones, or app interface; the renderer composites a real Ascend app surface onto each one.

All app imagery, including the insets on the transformation screens, is real Ascend app imagery already tracked in the repository:

- Screen 01 inset, live race: `web/public/images/ascend-live-climb-leaderboard-preview.png`
- Screen 02 inset, home: `web/public/images/ascend-home-live-climb.jpg`
- Screen 03, browse: `web/public/images/ascend-globe-browse.jpg`
- Screen 04, live race: `web/public/images/ascend-live-climb-leaderboard-preview.png`
- Screen 05, per-climb leaderboard: `web/public/images/ascend-climb-leaderboard.jpg`
- Screen 06, First Ascent: `web/public/images/ascend-climb-detail.jpg` with the real `FirstAscentBadgeDetailed` app asset
- Screen 07, Best Efforts: `web/public/images/ascend-best-effort-detail.png`

This mapping follows the approved brief in `docs/app-store-screenshots-brief.md`.

Two captures are deliberately unused:

- `ascend-live-climb-results.png` shows a split table that contradicts itself - a `25:00-23:53` interval that runs backwards and starts past the workout's own 23:53 duration, six rows under an "8 segments" header, and per-split steps summing to 2,596 against a stated 2,096 total. That is an app bug, not a capture problem; the screen cannot ship on a store listing that sells accurate measurement until the split calculation is fixed and it is re-captured.
- `ascend-live-climb-share.png` leads with "GLOBAL RANK 15th", which fights every headline in the set.

`device-frame.png` is the frame supplied by the `aso-appstore-screenshots` skill.

Run the renderer from the repository root after installing the website dependencies:

```bash
npm --prefix web ci
node data/ascend-support-page-and-product-page-package/render-screenshots.mjs
```
