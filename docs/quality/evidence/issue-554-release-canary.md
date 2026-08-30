# Issue 554 real-device release canary

Promotion to production remains blocked until this document is completed with real-device evidence from the exact candidate build.
Simulator tests and public provider manifests cannot prove Apple's authentication sheet, receipt delivery, rendered Superwall hit regions, or the complete provider bridge.

## Automation boundary

The ordinary suite directly purchases, disables renewal, forces renewal, expires, and refunds transactions through `SKTestSession`.
It deliberately does not wait for StoreKit's accelerated auto-renewal clock because that clock can fail to publish a billing-retry transaction when the complete test target is under load.
Deterministic RevenueCat fixtures prove that an active billing-issue entitlement routes into Ascend and that an inactive billing-retry entitlement stays gated.
This canary owns the remaining receipt-backed observation: Apple renewal failure, RevenueCat's resulting entitlement state, and Ascend matching that state.

## Candidate

- Build version: Pending human canary
- Build number: Pending human canary
- Git commit: Pending human canary
- Device and iOS version: Pending human canary
- Apple sandbox account trial eligibility: Pending human canary
- Date and operator: Pending human canary

## Required evidence

1. Launch the signed candidate while signed into the intended Firebase test account.
2. Confirm an already active `app_access` subscriber bypasses the gate after cold launch and foreground return.
3. Open `app_access_gate` for an inactive account and capture the selected annual and monthly localized price, period, renewal, and trial-eligibility states.
4. Confirm the rendered Close control does not cover or intercept the purchase CTA on a compact and a large iPhone.
5. Tap the annual CTA and record Apple's confirmation sheet appearing from that exact tap.
6. Complete the transaction and record the RevenueCat event or customer timeline identifier without recording a receipt, Apple account, Firebase UID, or other user identifier here.
7. Record active RevenueCat entitlement `app_access` and Ascend unlocking without a second purchase invitation.
8. Force quit and relaunch, then record persistent access.
9. Repeat the transaction path for monthly with no trial promise.
10. Exercise Restore Purchases for the same Apple account and record active access without a duplicate transaction.
11. Exercise no-subscription restore, offline restore, and delayed or pending approval copy and recovery controls.
    The app-hosted `SKTestSession` runner cannot drive Apple's user-interactive Ask to Buy or interrupted purchase sheet: `Product.purchase()` remains suspended waiting for that interaction.
    The automated suite therefore owns the RevenueCat pending result, disabled repurchase, and later entitlement-stream unlock, while this canary owns the real Apple sheet and transaction continuation.
12. Exercise a sandbox renewal failure with the release candidate and record RevenueCat's resulting `app_access` entitlement without recording account or receipt data.
    The committed StoreKit test catalog sets `_renewalBillingIssuesEnabled` to false, and the locked-subscriber recovery contract models billing grace as disabled.
    Those repository facts do not prove the live App Store Connect setting, so record the live setting before running this step.
    If live billing grace is disabled, expect an inactive RevenueCat entitlement and the recoverable access gate.
    If live billing grace is separately approved and enabled, expect an active RevenueCat entitlement and uninterrupted access to Ascend.
    Resolve the sandbox billing issue, then confirm RevenueCat returns `app_access` to active and Ascend unlocks without another purchase.
13. Confirm Terms, Privacy, Support, Manage Subscription, Restore Purchases, and Delete Account remain reachable while locked.
14. With VoiceOver enabled, verify the title is announced as a heading and focus follows loading, purchase, restore, pending approval, verification failure, and access confirmation in that order.
15. Dismiss Manage Subscription and Delete Account sheets and verify focus returns to the control that opened each sheet.
16. Repeat the locked-gate recovery path at the largest accessibility Dynamic Type size and verify no action, localized price, trial term, or renewal term is clipped or hidden.
17. Enable Reduce Motion and confirm progress remains understandable without relying on animation.
18. Enable Increase Contrast and confirm selected plans, focus indicators, status text, and destructive account controls remain distinguishable.
19. On compact and large iPhones, confirm every individual plan, Terms, Privacy, Support, Restore, Manage, Sign Out, and Delete Account control has an independently tappable target at least 44 by 44 points.
20. Confirm the complete recovery surface remains reachable in loading, timeout, offline, restore-not-found, pending, verification, and failed states.

## Evidence references

- Screen recording or screenshots: Pending human canary
- RevenueCat event reference: Pending human canary
- Superwall presentation reference: Pending human canary
- Entitlement and relaunch result: Pending human canary
- Reviewer sign-off: Pending human canary

No production or staging dashboard change is authorized by this checklist.
Publish provider fixes only through the separately approved human gate, rerun both live validators, then attach the completed evidence before promotion.
