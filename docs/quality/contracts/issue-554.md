# Feature Contract: Reliable subscription purchase and app-access gate

- Issue: #554
- Base branch: `develop`
- Change type: fix
- Owner: orchestrator

## User outcome

A climber who starts a free trial, buys a subscription, restores a subscription, already has access, or is waiting on Apple approval always sees one truthful next state and never gets invited to pay twice.
A verified RevenueCat `app_access` entitlement opens Ascend immediately on the device, while the Firebase access projection repairs independently in the background.
If the hosted Superwall experience cannot start a transaction, Ascend presents an equivalent native RevenueCat-backed annual and monthly checkout with clear recovery actions.

## Non-goals

- Do not add a freemium path or weaken Ascend's hard app-access gate.
- Do not unlock from a Superwall presentation, close, skip, or transaction event alone.
- Do not add a second StoreKit transaction owner or finish transactions outside the existing RevenueCat-owned purchase pipeline.
- Do not treat a client entitlement as authority for paid Firebase data access.
- Do not remove Restore Purchases, Terms, Privacy, subscription management, support, sign-out where available, or Delete Account from the locked-user recovery surface.
- Do not change prices, subscription periods, trial duration, or product identifiers in code.
- Do not mutate production or staging Superwall, RevenueCat, App Store Connect, Firebase, or analytics configuration without a separately approved human gate.
- Do not reintroduce `activeInCurrentEnvironment`; active access must be recognized in either StoreKit environment.

## Acceptance criteria

- [ ] AC-1: When RevenueCat's completed purchase response already contains active `app_access`, the purchase returns `.purchased`, publishes active client access, updates Superwall subscription status, and begins routing into Ascend without requiring another CustomerInfo request.
- [ ] AC-2: Firebase reconciliation runs as coalesced repair work after purchase or restore and can never delay, fail, or downgrade a verified RevenueCat purchase or restore terminal.
- [ ] AC-3: When a completed transaction does not yet contain active `app_access`, the app enters a non-repurchasable verification state, performs a bounded RevenueCat-only refresh, and later unlocks from the entitlement stream if access becomes active.
- [ ] AC-4: A pending or interrupted Apple purchase shows that approval or confirmation is pending, disables new purchase attempts, and can unlock later from the entitlement stream without reopening checkout.
- [ ] AC-5: Paywall presentation, purchase, restore, verification, and Superwall subscription-status callbacks are correlated to both a presentation attempt and the authenticated Firebase identity generation, so stale results after retry, sign-out, deletion, or account switching are ignored.
- [ ] AC-6: Hosted presentation has an injected, deterministic deadline covering registration through the first presented or terminal callback, cancels the deadline after presentation, and cannot leave the gate spinning forever.
- [ ] AC-7: A Superwall skip, presentation error, missing callback, invalid live artifact, or repeated deterministic dismissal exposes a native RevenueCat-backed fallback that offers only the configured annual and monthly packages and uses the same purchase executor.
- [ ] AC-8: The native fallback displays RevenueCat and StoreKit localized price, duration, renewal, and trial eligibility truthfully, and it never promises seven free days to an ineligible climber.
- [ ] AC-9: Restore is single-flight, bounded, cancellation-safe, identity-safe, and always settles into active access, no active Ascend subscription found, offline, timed out, cancelled, or provider failure with an actionable recovery path.
- [ ] AC-10: Existing active subscribers and subscribers in RevenueCat's active billing-grace state bypass the gate on cold launch, foreground, returning sign-in, and entitlement-stream updates, while expired and revoked subscriptions remain gated.
- [ ] AC-11: Purchased and restored states show access confirmation or verification without rendering purchase controls again while root routing catches up.
- [ ] AC-12: The gate uses plain, accurate copy for opening checkout, verifying access, pending approval, dismissal, offline, timeout, and provider failure, and retains accessible Restore Purchases, Manage Subscription, Terms, Privacy, Support, and Delete Account recovery actions.
- [ ] AC-13: A versioned validator checks the actual hosted Superwall Editor artifact and provider manifest for the production placements, expected product IDs, expected purchase action, valid state references, non-overlapping close action, and the exact `app_access` entitlement contract instead of treating repository HTML as proof of production behavior.
- [ ] AC-14: A committed StoreKit configuration and deterministic tests cover eligible annual trial, trial-ineligible annual purchase, monthly purchase, cancellation, pending approval, interrupted purchase, restore, renewal, expiration, billing retry or grace, refund or revocation, relaunch, and account switching at the layers the simulator can own.
- [ ] AC-15: The shared staging Test action exercises the Staging monetization configuration, PR CI runs deterministic fixture and parser checks without depending on provider HTTP availability, deploy preflight validates the live artifact, and release documentation blocks promotion until a real-device canary proves tap to Apple transaction to RevenueCat `app_access` to Ascend unlock and relaunch persistence.
- [ ] AC-16: Purchase, restore, paywall, watchdog, fallback, and stale-callback logic settles once per attempt with privacy-safe build, placement, presentation, provider outcome, identity-generation match, entitlement presence, StoreKit receipt environment, and recovery-path analytics, without logging user identifiers, receipt contents, prices, or raw provider errors.
  Delivery is refused when the attempt owner no longer matches the telemetry sink identity, so an old account's terminal can never be attached to the new account.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Authenticated identity not yet bound to RevenueCat | Keep the hard gate closed, show a bounded access check, and do not present or enable checkout until the current Firebase UID owns the RevenueCat identity generation. | Identity-barrier unit tests and rapid-account-switch journey test. |
| Entitlement resolving | Show `Checking your subscription access` with a deadline and no purchase controls until cached or refreshed subscription state resolves. | Resolver-state tests and snapshot. |
| Active `app_access` in production or sandbox | Route to the main app immediately and publish active Superwall status. | Any-environment entitlement tests and root-route tests. |
| Active billing grace | Treat RevenueCat's active entitlement as access and route to the main app. | Deterministic RevenueCat billing fixture plus the release canary's real receipt/provider observation. |
| Billing retry without active grace, expired, or revoked | Keep the user gated and offer subscription options and recovery actions. | Deterministic RevenueCat billing fixture, direct StoreKit expiration/refund evidence, and root-route tests. |
| Hosted paywall opening | Show `Loading subscription options` and start the presentation watchdog. | View-model clock test and snapshot. |
| Hosted paywall presented | Cancel the opening watchdog and allow the user unlimited reading and decision time. | Presenter and view-model clock tests. |
| Hosted CTA starts purchase | Record one transaction start, disable competing attempts, and transition to purchasing or Apple's sheet. | Hosted-artifact action validator and provider-simulation evidence. |
| Hosted paywall skipped, errors, or never calls back | Stop the spinner and load the native RevenueCat fallback. | Skip, error, and watchdog tests. |
| Hosted paywall dismissed before purchase | Explain that no purchase was made and offer native plans as the primary retry path. | Dismissal-state unit test and snapshot. |
| Native plans loading | Show a bounded loading state while keeping legal, restore, support, and account-deletion recovery available. | Native-paywall view-model clock test and snapshot. |
| Native plans ready | Show only configured annual and monthly plans with localized terms and accurate trial eligibility. | Package-mapping tests and snapshot. |
| Purchase cancelled | Confirm that no purchase was made and return to actionable plans without showing an error. | Purchase-executor test and state-machine test. |
| Purchase pending or interrupted | Explain that Apple approval or confirmation is pending, prevent repurchase, and listen for later entitlement activation. | Deterministic provider-result and entitlement-stream journeys, plus the TestFlight Ask to Buy canary. |
| Purchase response contains active `app_access` | Adopt active access immediately, return purchased, show access confirmation, and reconcile Firebase asynchronously. | Purchase-response authority test and slow-reconciliation test. |
| Purchase completes without propagated entitlement | Show `Confirming your access`, run bounded RevenueCat-only verification, prevent repurchase, and accept a later active stream update. | Delayed-entitlement tests with an injected clock. |
| Purchase verification times out | State that payment may still be processing, explicitly warn against purchasing again, and offer Check Access, Restore, Manage Subscription, and Support. | Timeout state test and snapshot. |
| Restore in progress | Disable duplicate restore and purchase actions and show a bounded restoring state. | Single-flight restore test. |
| Restore finds active `app_access` | Adopt access immediately, show confirmation, route into Ascend, and reconcile Firebase asynchronously. | Restore-success and slow-reconciliation tests. |
| Restore finds no active Ascend subscription | Say that no active Ascend subscription was found for the current Apple ID and keep plans and support actionable. | No-entitlement restore test and snapshot. |
| Offline with previously verified active access | Use RevenueCat's valid cached active entitlement for client routing while server-protected data remains server-authorized. | Offline cached-entitlement test. |
| Offline without verified active access | Keep the gate closed, fail fast with reconnect guidance, and never spin or grant access. | Offline presentation, purchase, and restore tests. |
| Sign-out, account deletion, or account switch during work | Cancel owned tasks, invalidate the attempt generation, ignore every late callback, refuse stale analytics delivery, and resolve only for the new identity. | Adversarial identity-transition and account-attributing sink tests. |
| Root routing lags after success | Show access confirmation or verification only, with no purchase CTA. | Presentation-state test and snapshot. |
| App leaves and returns | Resume from current entitlement truth, not stale view-local presentation state. | Foreground and relaunch journey tests. |

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| AC-1 | `PaywallPurchaseAnalyticsContractTests` and `RevenueCatEntitlementServiceTests` using purchase-returned active CustomerInfo with the refresh stub forced to fail. | It proves the first verified RevenueCat response is sufficient and a redundant fetch cannot turn success into failure. |
| AC-2 | `MonetizationManagerServerReconciliationTests` with never-returning, timed-out, and failed reconcilers plus `AppAccessReconciliationServiceTests` for overlapping callers. | It proves Firebase projection is background repair and concurrent repair requests coalesce. |
| AC-3 | `PaywallPurchaseAnalyticsContractTests` and `AppAccessPaywallCoordinatorTests` using an initially inactive response, bounded refresh, timeout, and later active stream update. | It proves propagation delay never becomes a second-purchase invitation. |
| AC-4 | `PaywallPurchaseAnalyticsContractTests.pendingPurchaseEmitsOnePendingTerminalAndReturnsSuperwallPending`, `AppAccessPaywallCoordinatorTests.pendingAndUnconfirmedPurchaseNeverInviteRepurchase`, and the Ask to Buy step in `issue-554-release-canary.md`. | It proves pending users remain safe and unlock without another checkout while reserving Apple's user-driven approval sheet for device evidence. |
| AC-5 | `MonetizationIdentityTransitionStateTests`, `TelemetryManagerTests.accountBoundDeliveryNeverCrossesTheSinkIdentity`, `PaywallPurchaseAnalyticsContractTests.accountSwitchDuringPurchaseSuppressesTheOldTerminalInsteadOfAttributingItToTheNewAccount`, `PaywallPurchaseAnalyticsContractTests.accountSwitchDuringPurchaseCancellationSuppressesTheOldTerminal`, `PaywallPurchaseAnalyticsContractTests.accountSwitchDuringRestoreSuppressesTheOldTerminalInsteadOfAttributingItToTheNewAccount`, `PaywallPurchaseAnalyticsContractTests.accountSwitchDuringRestoreCancellationSuppressesTheOldTerminal`, `HostedPurchaseRecoveryIntegrationTests.sdkDidPresentBeforeHandlerRecordsShownOnceForTheCapturedAccountOnly`, and `AppAccessPaywallCoordinatorTests.switchingTelemetryIdentityFirstSuppressesTheOldGateTerminalAndAttributesTheNewAttempt`. | It proves old purchase, restore, presentation, entitlement, and analytics work cannot affect or be attributed to the current account, including Superwall's delegate-before-handler callback order. |
| AC-6 | `AppAccessPaywallCoordinatorTests.missingHostedCallbackCancelsPresentationAndLoadsNativeFallback`, `presentedCallbackCancelsOpeningDeadlineAndRemainsHosted`, `cancellationPreventsLateNativeLoadAndHostedCallbackMutation`, and `retryIgnoresAnOlderSlowNativePlanLoad`. | It proves only startup is bounded, reading time is not, and cancelled or superseded work cannot mutate the current attempt. |
| AC-7 | `AppAccessPaywallCoordinatorTests.hostedTerminalLoadsNativeFallback`, `missingHostedCallbackCancelsPresentationAndLoadsNativeFallback`, and `scripts/test/superwall-live-artifact.test.mjs`. | It proves every hosted failure reaches a working RevenueCat path. |
| AC-8 | `NativeSubscriptionPlanMapperTests` for annual and monthly filtering, localized display values, eligible trial, ineligible trial, and missing products. | It proves checkout copy comes from provider truth and unsupported products never appear. |
| AC-9 | `AppAccessRestoreServiceTests`, `AppAccessRestoreStateTests`, `RestorePurchasesViewModelTests`, and `RevenueCatPurchaseControllerRestoreTests`. | It proves restore always settles once, coalesces provider work, ignores stale identity results, and remains recoverable. |
| AC-10 | `RevenueCatEntitlementServiceTests.activeBillingGracePayloadRoutesToTheMainAppWithoutRefetching`, `inactiveBillingRetryPayloadRoutesToThePaywallWithoutRefetching`, `MonetizationManagerPaywallTests`, `StoreKitSubscriptionLifecycleTests`, and `AppReviewSandboxEntitlementTests`. | It proves an active RevenueCat entitlement keeps access during billing grace, an inactive billing-retry entitlement stays gated, and the same routing holds across StoreKit environments. |
| AC-11 | `AppAccessPaywallPresentationStateTests`, `AppAccessPaywallCoordinatorTests`, and `AppAccessPaywallPlaceholderSnapshotTests`. | It proves a successful payer cannot see a fresh purchase invitation. |
| AC-12 | `AppAccessPaywallPlaceholderSnapshotTests`, `AppAccessRestoreStateTests`, `AccountRestoreAlertEvidenceTests`, and the accessibility steps in `issue-554-release-canary.md`. | It proves the recovery experience is truthful, usable, and has named device evidence for accessibility behavior. |
| AC-13 | `scripts/test/superwall-live-artifact.test.mjs`, versioned fixtures under `scripts/test/fixtures/superwall`, and the read-only `scripts/validate-superwall-live-artifact.mjs` deploy preflight. | It proves deterministic PR checks falsify malformed action graphs, while deploy preflight detects live provider drift without turning temporary provider HTTP failure into a PR dependency. Geometry remains a real-device tap-canary gate when the runtime artifact does not expose reliable hit frames. |
| AC-14 | `AscendSubscriptions.storekit`, `StoreKitSubscriptionLifecycleTests`, `RevenueCatEntitlementServiceTests`, `NativeSubscriptionPlanMapperTests`, `PaywallPurchaseAnalyticsContractTests`, `AppAccessPaywallCoordinatorTests`, and `issue-554-release-canary.md`. | It proves direct StoreKit session mutations, provider-result handling, and RevenueCat access mapping deterministically, while assigning Apple's clock-driven renewal, Ask to Buy, receipt propagation, and provider interpretation to the isolated release canary. |
| AC-15 | `scripts/test/storekit-subscription-contract.test.mjs`, `AscendApp-Staging.xcscheme`, deterministic PR CI, live staging and production deploy preflights, and `issue-554-release-canary.md`. | It proves local Test is representative, network availability is not a PR dependency, provider drift still blocks deployment, and the one integration chain automation cannot fully guarantee is recorded. |
| AC-16 | `TelemetryManagerTests.guardedDeliveryAndIdentityMutationAreAtomicInBothWinnerOrders`, `TelemetryManagerTests.lifecycleRecorderBuildsAnOwnerBoundEnvelopeAndRejectsStalePreflight`, `TelemetryManagerTests.staleLifecycleOwnerRefusalNeverReportsUnderTheNextAccount`, `functions/test/lifecycle.test.ts` legacy acceptance plus V2 owner match, missing, mismatch, and non-persistence cases, `functions/test/emulator/lifecycleFieldNotes.test.ts`, `PaywallPurchaseAnalyticsContractTests`, `PaywallPurchaseAnalyticsTranscriptTests`, `HostedPurchaseRecoveryIntegrationTests`, `AppAccessPaywallCoordinatorTests`, and `PrivacyAnalyticsClassification.md`. | It proves incidents can be reconstructed without collecting private purchase or identity data, sink identity cannot race guarded delivery, current iOS V2 lifecycle delivery is checked against authenticated server identity, stale owner refusals are not reported under a later account, delivery metadata is not persisted, and stale account-owned analytics are suppressed instead of being misattributed. |

## UX evidence

- Capture the hard gate, native annual and monthly fallback, Apple-pending state, access-verifying state, purchase-verification timeout, restore-not-found state, offline state, and access-confirmed state.
- Capture at least one compact iPhone and one large iPhone.
- The access gate intentionally keeps its branded dark surface when the system appearance is light, so the large light-system capture proves that the forced-dark gate remains legible rather than claiming a separate light visual treatment.
- Verify default Dynamic Type and an accessibility Dynamic Type size without clipped price, trial, legal, restore, support, or deletion controls.
- Verify VoiceOver reads plan name, localized cost and period, trial terms, selected state, purchase action, Restore Purchases, Manage Subscription, Terms, Privacy, Support, and Delete Account in a logical order.
- Verify Reduce Motion removes decorative motion without hiding progress or state changes.
- Record a real-device TestFlight canary showing hosted CTA tap, Apple confirmation sheet, RevenueCat entitlement, Ascend unlock, force quit, relaunch, and persistent access.

## Risk and rollout

- Authorization remains fail-closed for unknown, inactive, expired, and revoked states.
- RevenueCat's exact active `app_access` entitlement remains the client authorization source, and Firebase remains the server authorization source for paid backend data.
- Superwall remains presentation and analytics only, and RevenueCat remains the only transaction owner.
- Purchase and restore adoption must use the existing RevenueCat identity-generation contract from the latest `develop` branch rather than creating a parallel identity model.
- No data migration or Firestore schema change is expected.
- Analytics changes must remain low-cardinality and match the privacy manifest, privacy policy, and App Store privacy disclosures before release.
- A Firebase UID may be used only as internal delivery ownership metadata.
  It must never become an event parameter, and account-owned delivery must be refused after the telemetry sink has switched to another UID.
- The lifecycle callable temporarily accepts the authenticated legacy unversioned envelope so already-installed clients continue to work during rollout.
  Current iOS sends owner-bound V2, which validates the expected owner against callable authentication and strips delivery metadata before persistence.
  Legacy compatibility is not an authorization boundary and must be retired only through a separately versioned rollout after installed-client adoption is proven.
- The native fallback is a recovery path, not a replacement experiment, and it must preserve the same products and legal terms as the hosted paywall.
- Rollback may remove the new fallback UI or watchdog only if the purchase-response authority and asynchronous reconciliation fixes remain, because reverting those would reintroduce charged-but-locked behavior.
- Staging must pass pure logic, provider simulation, StoreKit Testing, and the hosted-artifact preflight before TestFlight.
- The ordinary test suite must not wait for StoreKit's accelerated auto-renewal clock.
- `StoreKitSubscriptionLifecycleTests` owns only direct `SKTestSession` operations: product purchase, auto-renew cancellation, forced renewal, expiration, and refund.
- `RevenueCatEntitlementServiceTests` owns deterministic app routing for active billing grace and inactive billing retry, while the release canary owns the real receipt-to-RevenueCat billing-state transition.
- Production promotion from `develop` to `main` is blocked until the separately approved provider configuration changes and real-device release canary are complete.

## Human gates

- Approve and publish the production and staging Superwall Editor artifact changes after a captured before-and-after diff, including the CTA action, malformed abandon state, Close behavior, copy, and entitlement alignment.
- Approve RevenueCat environment isolation and any resulting staging SDK key change before creating or moving products, apps, entitlements, offerings, or customers.
- Approve any App Store Connect subscription or server-notification mutation after verifying RevenueCat remains the notification owner.
- Run or observe the Apple sandbox or TestFlight real-device canary because Apple's payment authentication sheet and full provider receipt chain cannot be proven by simulator automation alone.
- Approve promotion of the completed `develop` change set into production `main` after CI, provider evidence, and the canary pass.
