# Launch-Readiness Audit

Date: June 11, 2026 · Branch audited: `feature/ascend-map-scene` (working tree)
Method: four parallel read-only passes — monetization, Live Climb hero loop, auth/account lifecycle, environments/release.

## Verdict summary

| Area | Verdict |
|---|---|
| Live Climb hero loop | **Ship-ready** — wired end-to-end, zero TODO/fatalError on the critical path |
| Monetization | **Plumbing wired; commerce config + trial promise missing** |
| Auth & account lifecycle | ~~Two App Review blockers in account deletion~~ - **both fixed** (see blockers 1-2) |
| Environments & release pipeline | **Solid** — one bundling verification + secrets checklist |

---

## 🔴 Launch blockers (code)

1. ~~**Account deletion leaves public mirrors behind.**~~ **Fixed** (issue #197). Mirrors are deleted before `user.delete()`, and the server-owned remainder is swept by the `cleanupDeletedUserData` Cloud Function.
2. ~~**No Sign in with Apple token revocation on account deletion.**~~ **Fixed** (issue #197). The `authorizationCode` is captured during Apple re-auth and revoked before the account goes away.
3. **Verify `PrivacyInfo.xcprivacy` lands in the Release bundle.** The manifest exists and is comprehensive (12 collected data types; UserDefaults CA92.1, FileTimestamp C617.1, DiskSpace E174.1, SystemBootTime 35F9.1; `NSPrivacyTracking=false`) but is **not referenced in project.pbxproj**. Build Release and `find` the file in the built .app; if absent, add to Copy Bundle Resources.

> Blockers 1-2 are resolved. The deletion ordering contract, the revocation rules, and what deliberately outlives an account are owned by **CLAUDE.md → Account Deletion (Apple 5.1.1(v))**; the ordering itself is locked in by `AscendAppTests/AccountDeletionServiceTests.swift`. Consult those rather than this dated snapshot.

## 🟡 Commerce configuration (dashboards — not auditable from code)

4. **App Store Connect:** create IAPs — yearly $49.99 w/ 7-day trial, monthly $9.99.
5. **RevenueCat:** products attached to entitlement `app_access`, offering `default` (the exact IDs the code expects — `MonetizationConfiguration.swift:43-44`).
6. **Superwall:** attach the imported paywall to a campaign on the app's placements — `onboarding_paywall` / app-access gate — and publish. Dashboard currently shows only "Example Campaign" and Revenue Tracking: Missing (RevenueCat→Superwall forwarding not set up).
7. **Sandbox test on device:** purchase → entitlement unlocks → restore works.

## 🟠 Promise vs. reality

8. **Trial-extension ("trial extends as you complete climbs") has zero implementation** — no model, no extension call on workout completion, no UI. Cut the claim for v1 or scope the feature. (Same overclaim class as the paywall's "100+ landmarks" line — see superwall-paywall notes.)
9. **No paywall-priming stage** in `PostAuthOnboardingStage` (stages: displayName, gender, age, weight, location, notifications, planLoading, firstClimb). Flow hits the hard gate cold after onboarding. Conversion polish, not a blocker.
10. **No fallback UI** on `AppAccessPaywallPlaceholderView` if Superwall config fails — users would see "unavailable" with no purchase path.

## 🟢 Pre-flight checklist (mechanical)

- GitHub secrets for production deploy: `APP_STORE_CONNECT_API_KEY_ID` / `_ISSUER_ID` / `_KEY`, `MATCH_GIT_URL` / `_PASSWORD` / `_GIT_PRIVATE_KEY`, `GOOGLE_SERVICE_INFO_PRODUCTION_BASE64`, `GCP_WORKLOAD_IDENTITY_PROVIDER_PRODUCTION` + `GCP_SERVICE_ACCOUNT_EMAIL_PRODUCTION`.
- Then flip repo variable `PRODUCTION_READY=true` (deploy-production.yml gate is wired and currently off).

## Secondary findings (lower priority, don't lose these)

**Monetization**
- Debug/Staging/Release all inject the **production** RevenueCat API key; an `AscendRevenueCatTestAPIKey` placeholder exists but isn't differentiated. Decide whether Debug should use a sandbox/test key.
- No StoreKit configuration file → can't test purchases in Simulator without sandbox. Optional QoL.
- Monetization test coverage is configuration-only (`MonetizationConfigurationTests`); no tests for entitlement transitions, paywall routing, or restore.
- Superwall placements defined in code: `.onboardingPaywall`, `.appLaunchHardGate`, `.appAccessGate` (`SuperwallPaywallPresenter.swift:38-44`).

**Live Climbs**
- Headphone readiness is checked at Climb Detail entry (`ClimbDetailView.swift:1407-1432`) but not re-checked at countdown start; a Bluetooth drop in between fails gracefully but UX could pre-empt. Nice-to-have.
- Climb image disk cache has **no eviction policy** — unbounded growth; monitor in production.
- No telemetry when replay-leaderboard fetches exhaust their timeout (operational blind spot, minor).
- Cloud Function `onWorkoutReplaySplitsWritten` (functions/src/liveReplayLeaderboard.ts) is exported, validated (source=headphone_motion, target reached), tested, and handles FA claims + entry replacement. Confirmed good.

**Auth/account**
- Client-side deletion has a **90-second timeout** (`DeleteAccountConfirmationView.swift:29`) — large media libraries could partially delete. The recommended server-side cleanup now exists (`functions/src/accountCleanup.ts`), triggered by the delete of `users/{uid}`; it is the authoritative sweep for server-owned data, not merely a safety net. Note it only fires once `users/{uid}` is actually deleted, so a client that times out before that step still leaves work for a later deletion attempt.
- Sign-out, re-auth flows (Apple + Google), and Internal QA gating (DEBUG/STAGING + project-ID allowlist) all confirmed correct.

**Config/release**
- The **staging plist is a symlink** to `~/.config/ascend/firebase/GoogleService-Info-Staging.plist` — local Staging builds fail without that directory (or `ASCEND_FIREBASE_PLISTS_DIR`). CI is unaffected (uses base64 secret). Document for any second machine.
- Bundle IDs per config: `com.TylerPavay.AscendApp[.dev|.staging]` + matching `.LiveClimbWidgets` widget IDs. Confirmed consistent.
- No hardcoded Firebase project IDs in Release code paths (URLs derive from `FirebaseApp.app()?.options.projectID`). Confirmed.
- Usage descriptions present: Motion, Health share/update, Photo library (+Add), Live Activities keys. Camera/ATT/LocalNetwork correctly absent (unused).

## Confirmed good (no action)

- Hard paywall gating is real in Release (`AppRootRoute.swift:45-63`; `allowsUnentitledAppAccess` compiles to false outside DEBUG/STAGING) with no runtime bypass.
- Restore purchases wired end-to-end (RootView → MonetizationManager → `Purchases.shared.restorePurchases()`).
- Post-auth onboarding properly blocks until profile completion; resolver handles first-time/returning/interrupted.
- Privacy boundaries enforced: other-user reads go through public mirrors; Storage prefixes owner-only.
- Production Firebase fully provisioned (`GoogleService-Info-Production.plist` for `ascend-prod-9c8f2` in repo); plist-copy build phase validates bundle ID + URL scheme per config.
- fastlane `build_production` / `upload_testflight` lanes and the gated production workflow are ready.
