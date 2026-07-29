# Ascend App Store product-page package

Locale: en-US

## Deliverables in this PR

- Support page: `web/src/pages/support.astro`, linked from the site footer and slide menu
- Final App Store copy: `app-store-copy.md`

## Screenshots are not in this PR

The seven-screen iPhone screenshot set was deliberately split into a separate design follow-up.
Iterative composition fixes kept regressing decisions that had already been approved, so the set
needs one deliberate design pass rather than another review round.

No screenshot set ships here. Two blockers remain open: screen 06 still shows a disabled
"Start Live Climb" CTA, and screen 02's inset is off-message against its Everest headline.

## Support URL

Production deployment was completed on July 28, 2026.
Both `https://ascendstepper.com/support` and `https://ascend-prod-9c8f2.web.app/support` returned
HTTP 200 after deployment, verified independently of the deploy tooling.

The deployed page predates the later presentation fixes in this PR (the topic-heading hierarchy and
the list-to-paragraph spacing); a redeploy after merge closes that gap. The HTTP 200 requirement
holds either way.
