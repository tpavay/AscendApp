# Subscription Paywall Setup

Last verified: July 27, 2026

This file is the authoritative repository guide for Ascend's launch subscription configuration.
The repo-controlled contract is enforced by `scripts/test/subscription-launch-offer.test.mjs`.

## Launch Offer

Both auto-renewing products unlock the same RevenueCat entitlement.

| Plan | Product identifier | Billing | Trial |
|---|---|---|---|
| Annual | `ascend_yearly` | `$49.99/year` | Seven days, then annual billing |
| Monthly | `ascend_monthly` | `$9.99/month`, charged immediately | None |

RevenueCat must use:

- Entitlement: `app_access`
- Current offering: `default`
- Annual package: `$rc_annual` containing `ascend_yearly`
- Monthly package: `$rc_monthly` containing `ascend_monthly`

The self-hosted Superwall paywall must bind `ascend_yearly` to product reference `primary` and `ascend_monthly` to product reference `secondary`.

There is no weekly launch product and no separate discounted launch offer.
Do not add either to a Superwall campaign, Hosting content, or release checklist.

## Verified Vendor State

The July 27, 2026 audit used RevenueCat's authenticated project integration and its linked App Store Connect state.

- App Store Connect reports `ascend_yearly` as a one-year subscription at `$49.99` in the United States with a one-week introductory trial.
- App Store Connect reports `ascend_monthly` as a one-month subscription at `$9.99` in the United States with no trial offer.
- Both App Store products are `READY_TO_SUBMIT`.
- RevenueCat has both products active and attached to `app_access`.
- RevenueCat offering `default` is current, with annual first and monthly second.
- RevenueCat has no third launch product.

The native purchase controller receives the StoreKit 2 product from Superwall and passes it to RevenueCat.
Keep localized native prices sourced from that StoreKit product.
Do not replace native StoreKit pricing with repository-hardcoded localized assumptions.

The Superwall dashboard could not be audited on July 27, 2026 because the available browser session required an operator login.
The repository paywall is final, but the dashboard campaign must remain disabled until an authenticated operator completes the verification checklist below.

## Environment Split

RevenueCat and Superwall keys are selected per build configuration through `ASCEND_REVENUECAT_API_KEY` and `ASCEND_SUPERWALL_API_KEY`.
The values reach the app through `Info.plist` substitution.

| Environment | Build configuration | Bundle ID | Monetization keys |
|---|---|---|---|
| Dev | `Debug` | `com.TylerPavay.AscendApp.dev` | Real local-development keys |
| Staging | `Staging` | `com.TylerPavay.AscendApp.staging` | `REPLACE_ME_` placeholders |
| Production | `Release` | `com.TylerPavay.AscendApp` | `REPLACE_ME_` placeholders |

Staging and production monetization remain non-functional until their placeholders are replaced.

- `MonetizationConfiguration` rejects any key with the `REPLACE_ME_` prefix.
- `scripts/ci/assert-monetization-keys-configured.mjs` fails Staging and Release archives before Fastlane.
- Non-Debug builds refuse to launch with unreplaced placeholder keys.

### Key replacement checklist

Replace all four settings in `AscendApp.xcodeproj`:

1. Replace the Staging `ASCEND_REVENUECAT_API_KEY` with that RevenueCat app's Apple publishable key.
2. Replace the Staging `ASCEND_SUPERWALL_API_KEY` with that Superwall app's public key.
3. Replace the Release `ASCEND_REVENUECAT_API_KEY` with that RevenueCat app's Apple publishable key.
4. Replace the Release `ASCEND_SUPERWALL_API_KEY` with that Superwall app's public key.

Leave `ASCEND_REVENUECAT_TEST_API_KEY`, `ASCEND_USE_REVENUECAT_TEST_STORE`, and `ASCEND_SUPERWALL_TEST_MODE` unchanged.
Update the deliberate `REPLACE_ME_` tripwires in `scripts/test/monetization-build-configuration.test.mjs` in the same change as real key replacement.
Never commit the real keys to documentation or test fixtures.

Each environment needs the same logical configuration:

- RevenueCat products `ascend_yearly` and `ascend_monthly`
- RevenueCat entitlement `app_access`
- RevenueCat current offering `default`
- Superwall placements `app_access_gate` and `onboarding_paywall`

## Dev Superwall References

These existing IDs belong only to the development Superwall project:

- Project: `24464`
- iOS application: `47442`
- Existing campaign: `90307`
- Existing example paywall: `232089`
- Hard-gate placement: `app_access_gate`
- Onboarding experiment placement: `onboarding_paywall`

Do not reuse development IDs for Staging or Production.

## Self-Hosted Paywall

The only launch paywall page copied into `web/dist` by the Astro build is:

- Source: `web/public/superwall/onboarding-paywall.html`
- Shared styles: `web/public/superwall/ascend-paywall.css`
- Production URL: `https://ascendstepper.com/superwall/onboarding-paywall.html`

The page defaults to Annual.
Its visible state must remain:

### Annual selected

- Headline: `Try 7 Days Free`
- Price: `$49.99/year`
- Plan disclosure: `7 days free, then billed annually`
- CTA: `Try 7 Days Free`
- Legal disclosure: `7 days free, then $49.99/year. Auto-renews until canceled.`
- Product reference: `primary`

### Monthly selected

- Headline: `Climb With Full Access`
- Price: `$9.99/month`
- Plan disclosure: `Charged immediately, then monthly`
- CTA: `Subscribe for $9.99/month`
- Legal disclosure: `$9.99 charged now, then monthly. Auto-renews until canceled.`
- Product reference: `secondary`
- No trial badge, promise, CTA, or disclosure

Both states preserve Restore, Terms, Privacy, VoiceOver selection state, and the same purchase analytics path through Superwall and RevenueCat.

## Superwall Verification Checklist

Complete these steps in each authenticated Superwall project without publishing an unverified campaign:

1. Confirm the project has only `ascend_yearly` and `ascend_monthly` in the launch paywall.
2. Bind `ascend_yearly` to `primary`.
3. Bind `ascend_monthly` to `secondary`.
4. Point the paywall at `https://ascendstepper.com/superwall/onboarding-paywall.html`.
5. Confirm Annual is selected when `Try 7 Days Free` is visible.
6. Switch to Monthly and confirm the headline, CTA, price, and legal disclosure all describe an immediate monthly charge with no trial.
7. Confirm Restore, Terms, and Privacy still work.
8. Confirm a sandbox annual purchase and monthly purchase each grant `app_access`.
9. Wire the verified paywall to `app_access_gate`.
10. Keep onboarding experiments on `onboarding_paywall`.
11. Publish only after editor and device previews match the two states above.

## Release Gate

Before the first review submission:

1. Replace Staging and Release placeholder keys through the approved secret/configuration workflow.
2. Run `node --test scripts/test/*.test.mjs`.
3. Run the Staging iOS test suite.
4. Build the unsigned Release configuration.
5. Build the website and confirm the retired discount page returns 404.
6. Complete sandbox purchase and restore tests on a device.
7. Verify the enabled Superwall campaign targets `app_access_gate` and contains no weekly or separate discount variant.
