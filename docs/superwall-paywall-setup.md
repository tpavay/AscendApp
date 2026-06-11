# Superwall Paywall Setup

Date: 2026-06-10

## Superwall IDs

- Project: `24464`
- iOS application: `47442`
- App placement already used by the iOS app: `onboarding_paywall`
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

## Remaining Setup

1. Confirm App Store product identifiers for yearly trial, monthly, and optional discount offer.
2. Create or repair the two Superwall paywall records.
3. Attach product references:
   - yearly trial as `primary`
   - monthly as `secondary`
   - discount offer as `primary` on the one-time offer paywall
4. Wire the main paywall to `onboarding_paywall`.
5. Keep the campaign disabled until the editor preview renders correctly and RevenueCat entitlements are verified.
