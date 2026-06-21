# Superwall Paywall Setup

Date: 2026-06-10

## Superwall IDs

- Project: `24464`
- iOS application: `47442`
- App placement used by the iOS hard gate: `app_access_gate`
- App placement reserved for onboarding-specific paywall tests: `onboarding_paywall`
- Existing default campaign: `90307`
- Existing default example paywall: `232089`

## Uploaded Superwall Assets

- `ascend-paywall-stair-stepper-hero`
  - Superwall asset ID: `4887414`
  - Use for the small top hero on the main trial paywall.
- `ascend-paywall-staircase-background`
  - Superwall asset ID: `4887415`
  - Use for the one-time offer background.
- `ascend-a-mark`
  - Superwall asset ID: `4887416`
  - Use for the Ascend wordmark mark.

## Self-hosted Draft Pages

These pages are built locally and copied into `web/dist` by `npm --prefix web run build`:

- `web/public/superwall/onboarding-paywall.html`
- `web/public/superwall/one-time-offer.html`
- Shared CSS: `web/public/superwall/ascend-paywall.css`

Intended hosted URLs after the website is deployed:

- `https://ascendstepper.com/superwall/onboarding-paywall.html`
- `https://ascendstepper.com/superwall/one-time-offer.html`

Temporary Firebase Hosting preview URL, deployed on 2026-06-10 and expiring 2026-06-17:

- `https://ascend-staging-fa7d5--superwall-paywall-2zr8lg3k.web.app/superwall/onboarding-paywall`
- `https://ascend-staging-fa7d5--superwall-paywall-2zr8lg3k.web.app/superwall/one-time-offer`

## Main Trial Paywall

Copy:

- Headline: `Try 7 Days Free`
- Benefits:
  - `Choose from 100+ landmarks to climb`
  - `Improve with personalized climbing plan`
  - `Track records and ascents`
- Yearly plan:
  - Badge: `7 DAYS FREE`
  - Subtitle: `$49.99/year billed annually`
  - Price: `$4.16/mo`
  - CTA: `TRY 7 DAYS FREE`
  - Footer note: `No payment due now. Cancel anytime.`
- Monthly plan:
  - Subtitle: `Billed monthly`
  - Price: `$12.99/mo`
  - CTA: `UNLOCK EVERYTHING`
  - No free-trial footer note.
- Footer: `RESTORE`, `TERMS`, `PRIVACY`

Product reference names expected by the self-hosted page:

- `primary`: yearly free-trial product
- `secondary`: monthly product

Superwall product identifiers currently present in project `24464`:

- `ascend_yearly`
- `ascend_monthly`

## One-time Offer Paywall

Copy:

- Eyebrow: `ONE-TIME OFFER`
- Headline: `GET 50% OFF`
- Detail: `Unlimited access for $24.99 / year`
- Detail emphasis: `Just $2.08/mo`
- CTA: `CLAIM OFFER`
- Footer: `RESTORE`, `TERMS`, `PRIVACY`

Product reference expected by the self-hosted page:

- `primary`: yearly discount product or promotional offer

## Current Blockers

Superwall accepted the organization API key and asset uploads, but the paywall creation endpoints returned internal Superwall errors:

- `POST /v2/paywalls` with self-hosted URLs failed because the URLs are not live yet.
- `POST /v2/paywalls` with live Firebase Hosting preview URLs also failed with the same `Failed to store paywall URL` error.
- `POST /v2/paywalls` from public templates failed with `Failed to store paywall URL`.
- `POST /v2/paywalls` blank creates failed with `Failed to store paywall URL`.
- `POST /v2/paywalls/{id}/duplicate` failed with `Failed to store snapshot`.

This is not an authorization issue: the same key successfully wrote assets. Use the dashboard editor or Superwall support for the paywall record creation failure, or deploy the self-hosted pages and retry URL-based creation.

API check on 2026-06-19:

- Paywalls: `232127`, `232372`, and `232373` are all draft `New Paywall` records with no attached products.
- Existing campaign `90307` is still `Example Campaign` and only listens to placement `campaign_trigger`.
- The campaign variant still references archived example paywall `232089`.
- The iOS app hard gate now registers placement `app_access_gate`, so no live Superwall campaign will present until a campaign owns that placement.

## Remaining Setup

1. Confirm App Store Connect and RevenueCat both use product identifiers `ascend_yearly` and `ascend_monthly`, or update Superwall product identifiers to match the final App Store IDs.
2. Create or repair the two Superwall paywall records.
3. Attach product references:
   - `ascend_yearly` as `primary`
   - `ascend_monthly` as `secondary`
   - discount offer as `primary` on the one-time offer paywall
4. Wire the main hard-gate paywall to `app_access_gate`.
5. Optionally wire onboarding-specific experiments to `onboarding_paywall` once the onboarding paywall stage exists.
6. Keep the campaign disabled until the editor preview renders correctly and RevenueCat entitlements are verified.
