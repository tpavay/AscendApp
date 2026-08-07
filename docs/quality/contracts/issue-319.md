# Feature Contract: Minimum supported version gate

- Issue: #319
- Base branch: `develop`
- Change type: feature
- Owner: orchestrator

## User outcome

After a successful Remote Config resolution at launch or foreground, a climber below the minimum supported app version must update before continuing, while a climber below only the recommended version may update or defer the prompt.
All other climbers, including anyone whose configuration cannot be fetched or parsed, continue normally.

## Non-goals

- Do not arm either version parameter with a value above `0.0.0`.
- Do not publish Remote Config to dev, staging, or production.
- Do not change the behavior, defaults, or keys of the existing Boolean kill switches.
- Do not implement App Store release or review automation.

## Acceptance criteria

- [ ] AC-1: `remoteconfig.template.json` contains STRING parameters for minimum supported and recommended app versions, both defaulting to `0.0.0`.
- [ ] AC-2: Version policy is evaluated against `CFBundleShortVersionString` only after the launch or foreground Remote Config fetch resolves successfully.
- [ ] AC-3: A current version below the valid minimum version produces a non-dismissible update-required sheet with one App Store button and no Later or escape action.
- [ ] AC-4: A current version at or above the minimum but below the valid recommended version produces a dismissible update prompt with App Store and Later actions.
- [ ] AC-5: A current version at or above both valid thresholds proceeds without an update prompt.
- [ ] AC-6: Missing, empty, whitespace-only, malformed, or otherwise unparseable versions fail open. An unparseable current version fails the whole evaluation open; an unparseable threshold fails open on its own terms only, so neither threshold can suppress the other.
- [ ] AC-7: Version ordering is semantic, including numeric component ordering such that `1.10.0` is newer than `1.9.0`.
- [ ] AC-8: Fetch failure fails open for the version gate and never turns a persisted or default value into a blocking decision for that evaluation. It also never repeals a required lockout a successful fetch already resolved, so going offline is not a bypass.
- [ ] AC-9: The gate reevaluates after a resolved launch fetch and after each resolved foreground fetch.
- [ ] AC-10: The existing Boolean Remote Config kill switches retain their current defaults, persistence, real-time update behavior, and failure posture.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Below minimum after successful resolution | Non-dismissible required-update sheet with one App Store action | Policy unit tests and hosted UI evidence |
| Below recommended only after successful resolution | Dismissible recommended-update prompt with Update and Later | Policy, presentation-state, and hosted UI tests |
| At or above both thresholds | App proceeds with no prompt | Policy unit tests |
| Fetch pending | No version decision is made from unresolved values | Service lifecycle test |
| Fetch failure/offline | App proceeds with no version prompt, and an already-armed required lockout stays up | Service failure tests |
| Missing, empty, or malformed version | App proceeds with no version prompt | Parameterized parser/policy tests |

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| AC-1 | Remote Config template contract test | Pins both parameter types and inert defaults |
| AC-2 | Remote Config service launch-resolution test | Proves evaluation occurs only after a successful launch resolution |
| AC-3 | Version policy test plus required-update hosted UI evidence | Proves blocking state and absence of dismissal controls |
| AC-4 | Version policy and presentation-state tests plus recommended-update hosted UI evidence | Proves the prompt can be deferred |
| AC-5 | Version policy boundary tests | Proves equality and newer versions proceed |
| AC-6 | Parameterized malformed-input tests | Proves every invalid input fails open |
| AC-7 | Semantic version ordering tests | Proves numeric components are compared numerically |
| AC-8 | Remote Config service fetch-failure test | Proves a failed resolution produces no version-gate decision |
| AC-9 | Remote Config service foreground-resolution test | Proves every successfully resolved foreground refresh reevaluates the gate |
| AC-10 | Existing Remote Feature Flag resolution test suite | Guards the established kill-switch contract |

## UX evidence

Capture the required and recommended prompts on an iPhone 16 Pro simulator in dark mode.
Verify the one-button required state, the two-action recommended state, VoiceOver labels and modal behavior, Dynamic Type layout, and the absence of an interactive dismissal path for the required state.

**Also verify the `.paywall` route.**
The gate presents through a single `.sheet` on `RootView`, and Superwall presents its paywall outside that hierarchy.
An unentitled climber who cold-starts below the minimum is exactly the population that hands off to Superwall on `onAppear`, so confirm on a device that the required sheet is visible and not occluded before relying on the lockout mid-incident.

## Risk and rollout

This is a high-blast-radius remote control because an incorrectly armed minimum can lock out the installed base and App Review.
Both STRING parameters ship at `0.0.0`, invalid or unavailable values fail open, and no environment is published by this change.
A future operator must never set the minimum above the highest version that has already passed review and shipped, must scope the value with a Firebase App version condition, and must rehearse the exact condition and App Store link on Staging before a production incident.
Those rules live in `docs/remote-config-kill-switches.md` under "The version policy parameters, which are captain-only", which is the document an operator opens mid-incident; this contract is not.
There is no data migration, new user data collection, analytics event, privacy-manifest change, authorization change, or persisted-data write.

## Human gates

- The captain owns Remote Config publishing and the Staging rehearsal after merge.
