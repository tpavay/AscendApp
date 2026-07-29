# App Store screenshot sources

The two transformation photographs were generated specifically for Ascend with the built-in OpenAI image generator.
They contain no text, logos, phones, or app interface.

The five feature screenshots use real Ascend app imagery already tracked in the repository:

- Browse: `web/public/images/ascend-globe-browse.jpg`
- Live race: `web/public/images/ascend-live-climb-leaderboard-preview.png`
- Leaderboard: `web/public/images/ascend-climb-leaderboard.jpg`
- First Ascent: `web/public/images/ascend-climb-detail.jpg` with the real `FirstAscentBadgeDetailed` app asset
- Best Efforts: `web/public/images/ascend-best-effort-detail.png`

`device-frame.png` is the frame supplied by the `aso-appstore-screenshots` skill.

Run the renderer from the repository root after installing the website dependencies:

```bash
npm --prefix web ci
node data/ascend-support-page-and-product-page-package/render-screenshots.mjs
```
