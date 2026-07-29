# Ascend App Store product-page package

Locale: en-US

## Deliverables

- Final App Store copy: `app-store-copy.md`
- Final iPhone screenshot set: `screenshots/iphone-6.9-en-US/`
- Screenshot source manifest: `screenshot-sources/README.md`
- Screenshot renderer: `render-screenshots.mjs`
- Seven-screen review sheet: `qa/app-store-contact-sheet.png`

## Screenshot set

The upload-ready directory contains exactly seven portrait PNG files.
Every file is 1320 x 2868 pixels, uses sRGB, and has no alpha channel.
This is the accepted 6.9-inch iPhone size requested by the submission audit.

The first two screens use generated transformation photography and contain no app interface.
The final five screens use real Ascend app captures, with the real First Ascent app asset used as a marketing breakout on screen six.

No iPad screenshots were created because the production app target is iPhone-only.

## Support URL

Production deployment was completed on July 28, 2026.
Both `https://ascendstepper.com/support` and `https://ascend-prod-9c8f2.web.app/support` returned HTTP 200 after deployment.
