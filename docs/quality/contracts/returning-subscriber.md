# Feature Contract: Restore Returning Subscriber Access

- Issue: Not required: the 2026-07-29 Firstmate launch brief explicitly directs this isolated implementation without assigning an issue.
- Base branch: `main`
- Change type: fix
- Owner: orchestrator

## User outcome

A paying subscriber who signs out can return directly to authentication, sign back in, and wait on a neutral Ascend loading surface until their RevenueCat identity is resolved.
An active subscriber then enters the app without seeing the paywall.

## Non-goals

- Do not change demographic fields, profile publication, profile display, report actions, or block actions.
- Do not change subscription products, entitlement identifiers, purchase ownership, or restore semantics.
- Do not grant access while entitlement state is unknown.

## Acceptance criteria

- [ ] AC-1: The signed-out welcome screen provides a direct, accessible "Already have an account? Sign in" route to the existing authentication screen.
- [ ] AC-2: Entitlement routing distinguishes `.unknown` from `.inactive`, and `.unknown` resolves to a loading route rather than the paywall.
- [ ] AC-3: A sign-out followed by sign-in prepares an unknown entitlement state synchronously and does not evaluate inactive access until the matching RevenueCat identify operation resolves.
- [ ] AC-4: An active subscriber who signs back in reaches the main app without the app-access paywall being registered or shown.
- [ ] AC-5: Stale identity completions from a signed-out or superseded account cannot overwrite the current identity's entitlement decision.
- [ ] AC-6: The app-access paywall handoff uses a neutral dark loading surface with no disabled call to action or "Access Required" dead-end message.
- [ ] AC-7: The hosted paywall document paints a dark canvas before its external stylesheet loads, preventing the white loading flash.
- [ ] AC-8: No sleep, delay, retry loop, or time-based routing workaround is introduced.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Happy path | Returning active subscriber signs in and reaches the main app without a paywall. | Sign-out/sign-in state-machine test and final simulator evidence. |
| Loading | Unknown or identifying entitlement shows a neutral dark setup/loading surface. | Route resolver test and app-access loading snapshot. |
| Empty | Confirmed inactive entitlement routes to the paywall handoff. | Route resolver test. |
| Error/offline | Unknown entitlement remains unresolved and never becomes a false inactive decision. | Route resolver test and entitlement service failure test. |
| Superseded identity | A stale completion cannot publish access for the current account. | Controlled async identity test. |

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| AC-1 | Landing screen UI evidence and accessibility review. | Shows the returning-user action is visible, direct, and usable. |
| AC-2 | `AppRootRouteResolverTests.resolvesWhileAccessStateIsUnknown`. | Fails if unknown is treated as paywall/no-access. |
| AC-3 | Monetization identity transition test covering reset then identify. | Observes unknown routing before identify completes. |
| AC-4 | Returning active subscriber route test with paywall presenter spy. | Fails if the paywall is registered before active identity resolution. |
| AC-5 | Superseded identity completion test. | Forces completion ordering and checks stale state is discarded. |
| AC-6 | Updated app-access loading snapshot and simulator screenshot. | Shows the cold-start handoff has no lock wall or disabled button. |
| AC-7 | Static hosted-paywall markup test and rendered browser evidence. | Verifies the initial document contains inline dark canvas styling. |
| AC-8 | Diff review and test-adversary inspection. | Detects time-based race masking. |

## UX evidence

- Capture the welcome screen and direct transition to authentication on an iPhone 16 Pro or newer simulator.
- Capture the entitlement-resolution loading surface in dark mode.
- Capture the app-access paywall handoff from app loading surface to hosted paywall with no white frame.
- Review VoiceOver labels, 44-point targets, and large Dynamic Type behavior for the new sign-in action.

## Risk and rollout

This change does not migrate data, change analytics identity values, alter privacy collection, or change subscription products.
Identity transitions are guarded so late provider responses cannot become the current account's authorization state.
The hosted paywall adds only critical first-paint styling before the existing stylesheet.
Rollback is a normal application and hosting rollback, with no persistent schema dependency.

## Human gates

- Final Apple sandbox smoke testing requires a configured sandbox Apple account if none is available to automation.
