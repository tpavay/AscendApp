# Ascend App Store product-page package

Locale: en-US

## Deliverables in this PR

- Support page: `web/src/pages/support.astro`, linked from the site footer and slide menu
- Final App Store copy: `app-store-copy.md`

## Screenshots

The seven-screen iPhone set was split out of this package and now lives under `AppStoreAssets/`.
See `AppStoreAssets/README.md` for the delivered files and the renderer that produces them.

## Support URL

Production deployment was completed on July 28, 2026.
Both `https://ascendstepper.com/support` and `https://ascend-prod-9c8f2.web.app/support` returned
HTTP 200 after deployment, verified independently of the deploy tooling.

The deployed page predates the later presentation fixes in this PR (the topic-heading hierarchy and
the list-to-paragraph spacing); a redeploy after merge closes that gap. The HTTP 200 requirement
holds either way.
