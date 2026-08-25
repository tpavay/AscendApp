# Feature Contract: Guideline 1.2 Block, Report, and Identity Filtering

- Issue: Not required: the 2026-07-29 firstmate launch brief explicitly authorizes implementation without a GitHub issue
- Base branch: `develop`
- Change type: feature
- Owner: orchestrator

## User outcome

Signed-in climbers see account-authored public names and photos, can block or report another climber from that climber's profile, and have blocked identities hidden immediately and consistently without changing rankings or workout data.
Blocks follow the account to new devices, and saved display names are screened before publication.

## Non-goals

- Do not remove or reorder blocked leaderboard rows.
- Do not hide rank, steps, time, pace, age, gender, city, height, weight, or other approved demographic and performance fields.
- Do not make reporting automatically block a user.
- Do not make blocking automatically report a user unless the blocker explicitly selects the optional report checkbox.
- Do not add inline, long-press, or mid-climb moderation menus.
- Do not add automated image moderation.
- Do not deploy Firebase changes, submit the app, or mutate production moderation data from this worktree.

## Acceptance criteria

### Part A - account-authored public identity

- [ ] PA-1: `PublicClimberIdentity.mode` is `.accountAuthored`, so a stored display name and photo are shown while a missing name falls back to the stable system handle.
- [ ] PA-2: Public profile writes persist the account's validated stored display name and bounded photo URL rather than the `Climber` placeholder, and a `leaderboard_stats` row carries that same validated identity - resolved by the server from the mirror through `leaderboardIdentityFields` in `functions/src/leaderboardStats.ts`, never written by a client.
- [ ] PA-3: The same bounded profanity and photo policy screens every public name, in both places a name can enter public data. The Firestore rules apply it to the client-writable documents (`isAllowedDisplayName` on the user root, plus `hasVisibleDisplayName`, `isAllowedDisplayName`, and `isValidPublicPhotoURL` on `users/{uid}/public_profile/current`, which bounds photo URLs to 2,048 characters and to the Firebase Storage host). The server derivation applies it again on the way out, replacing a mirror name that fails the screen with the account's stable system handle and re-bounding the photo, so no unscreened name can reach a public row.
  > PA-2 and PA-3 describe a relocation with defence in depth, not a relaxation.
  > `leaderboard_stats` is `allow write: if false` and server-derived (#307), so the four per-write leaderboard identity validators the rules used to carry have no document left to guard and were deleted.
  > Enforcement did not move with them: it now runs twice, once at the rules layer on the client-writable mirror and again in `publicIdentityFromData` when the server projects that mirror onto a row.
  > A row written before the policy existed, or a seeded mirror holding a disallowed name, is screened on the way out even though nothing screened it on the way in.
- [ ] PA-4: Global leaderboard rows and podium, Live Replay, per-climb completion leaderboard, First Ascent, community avatars, and other-user profile render actual stored public identity before block masking.
- [ ] PA-5: Deleted accounts continue to render `Anonymous Climber` with no photo.
- [ ] PA-6: Profile photo and display-name edits propagate to public profile and existing leaderboard mirrors without changing ranking data.
- [ ] PA-7: Part A ships only with the complete Part B moderation boundary in this same change.
- [ ] PA-8: The user root may keep an empty display name before onboarding completes, but every public mirror stores a non-empty validated account name or stable UID-derived fallback.
- [ ] PA-9: No historical backfill ships to production **in this change**, because the production database it shipped against held no user or projection data, so account-authored identity reached every projection through the live write path and the server propagation trigger only. Dev and staging repair pre-policy mirrors with `scripts/restore-public-identities.mjs`, which writes only the public profile source document and is refused against production.
  > **This criterion is not a precedent, and no later change may inherit it.**
  > It was satisfied by a measurement of an empty production database, not by a rule that identity policy never needs a backfill.
  > Production has held real climbers' identity and projection data since the App Store launch, so the same decision made today would leave real pre-policy rows unrepaired.
  > `docs/production-backend-rollout-runbook.md` is the single owner of what production contains and of the backfill obligation that follows; count the affected production rows there before deciding, and never restate the premise here.
- [ ] PA-10: Public profile propagation updates leaderboard, Live Replay entry, finisher, and First Ascent identity with bounded retry and leaves all non-identity fields unchanged.

### Part B - block, report, and write-time filtering

- [ ] AC-1: The only profile moderation affordance is the overflow menu on another user's profile, and it offers Block and Report.
- [ ] AC-2: Block completes without a required reason and updates the viewer's identity rendering immediately.
- [ ] AC-3: Block persists in `users/{blockerUid}/blocked/{blockedUid}`, hydrates on sign-in, and survives sign-out, sign-in, and a new device.
- [ ] AC-4: A blocked leaderboard entry remains in place with the same rank, steps, times, pace, and demographic values while only its display name and photo are replaced by a neutral placeholder and generic avatar.
- [ ] AC-5: Every cross-user identity surface uses one shared resolver, including global leaderboard rows and podium, Live Replay, per-climb completion leaderboard, First Ascent attribution, community avatars, and other-user profile.
- [ ] AC-6: Live Replay rows, per-climb completion rows, and community avatars navigate to the same other-user profile destination as global leaderboard entries.
- [ ] AC-7: A blocked climber can be unblocked from a Blocked climbers list in Settings.
- [ ] AC-8: Reporting requires a reason and creates a queue item with reported uid, reporter uid, reason, timestamp, and source surface without otherwise changing the reporter's view.
- [ ] AC-9: Blocking creates no report by default and creates one only when the blocker explicitly selects Also report this profile and chooses a required reason.
- [ ] AC-10: Firestore rules allow users to read and write only their own block documents, allow report creation without report reads or mutations, and reject cross-user or malformed requests.
- [ ] AC-11: Display-name write paths reject objectionable names before persisting or publishing them.
- [ ] AC-12: Automated tests fail if blocked real names or photos escape the shared resolver or if rules permit cross-user block-list or report access.
- [ ] AC-13: The existing in-app support contact and App Store listing support URL are verified and recorded as submission evidence.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Happy path | Profile actions complete, identities resolve through the shared policy, navigation reaches profiles, and settings supports unblock. | Swift Testing, Firestore emulator rules tests, simulator interaction evidence |
| Loading | Profile, block-list hydration, and report submission show bounded progress without leaking an unverified identity. | Swift Testing and simulator interaction evidence |
| Empty | Blocked climbers shows a branded state-then-action empty state and no destructive control. | Simulator screenshot and accessibility inspection |
| Error/offline | Failed block, unblock, hydration, or report writes preserve server-authoritative state and present a retryable error. | Repository/store unit tests and simulator interaction evidence |

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| PA-1, PA-4, PA-5 | Public identity and audited identity-surface tests | Confirms account-authored values, stable fallback, deleted-account anonymity, and block masking across every public surface |
| PA-2, PA-3, PA-6, PA-8 | `tests/firebase-rules/moderation-contract.test.mjs` (the shared display-name screening vector against the user root and the public profile mirror) plus `functions/test/publicIdentity.test.ts` and the identity cases in `functions/test/leaderboardStats.test.ts` | Confirms both layers: the rules reject an objectionable or unbounded name on every client-writable publication, and the server resolver masks a disallowed name and an off-host photo before either reaches a derived leaderboard row. Also covers the pre-onboarding root exception, non-empty public fallbacks, and edit propagation |
| PA-7 | Feature diff and complete Part B test suite | Confirms public identity is not separated from its moderation controls |
| PA-9 | `scripts/test/production-backend-rollout.test.mjs` | Confirms the runbook orders the identity backend ahead of the publishing binary, states that production now holds real user data, and voids the no-backfill conclusion rather than letting a later change inherit it |
| PA-10 | Cloud Function identity propagation and stable-handle parity tests | Confirms profile edits converge across every projection with exact identity-only writes and bounded retry |
| AC-1 | Other-user profile view inspection and UI interaction evidence | Confirms the single approved placement and available actions |
| AC-2 | Blocked-identity store and resolver tests | Confirms no reason is required and the local render cache changes immediately after server success |
| AC-3 | Moderation store hydration tests and Firestore repository tests | Confirms remote persistence and account-scoped hydration semantics |
| AC-4 | Identity resolver value-preservation tests | Confirms only name and photo change while row data remains intact |
| AC-5 | Shared identity resolver tests plus source-boundary architecture test | Confirms every audited surface resolves through the central identity path |
| AC-6 | Navigation call-site tests or simulator interaction evidence | Confirms each audited surface reaches the other-user profile |
| AC-7 | Blocked climbers store/view tests and simulator interaction evidence | Confirms reversible settings management |
| AC-8 | Moderation report repository tests and Firestore rules tests | Confirms required reason and complete queue payload with create-only authorization |
| AC-9 | Block workflow tests | Confirms the optional report branch is explicit and no silent report occurs |
| AC-10 | `npm run test:firebase-rules` | Exercises owner-only blocks and create-only reports against the emulator |
| AC-11 | Display-name policy and publication service tests | Confirms objectionable names cannot reach persistence |
| AC-12 | Controlled resolver fault injection and rules-negative tests | Confirms critical protections produce meaningful test failures |
| AC-13 | In-app link inspection, support-page HTTP verification, and App Store metadata read | Confirms both published contact paths are reachable |

## UX evidence

- Record the other-user profile overflow, block confirmation, immediate placeholder rendering, report reason picker, report submission, Blocked climbers list, and unblock flow on an iPhone simulator.
- Capture the global leaderboard, Live Replay, per-climb leaderboard, community avatar stack, First Ascent attribution, and other-user profile with a blocked identity.
- Verify the compact supported iPhone size and a large iPhone size.
- Verify default and accessibility-extra-extra-extra-large Dynamic Type.
- Verify VoiceOver labels, reading order, focus restoration after sheets, and minimum 44-point action targets.
- Verify dark and light themes.

## Risk and rollout

Firestore rules must deploy to dev, staging, and production before or alongside the app binary because the new client writes use strict schema validation.
The `entries.userId` and `finishers.userId` collection-group indexes and the retry-enabled identity propagation function must deploy before the binary that publishes account-authored identity, so the first published profile propagates from the start.
The client remains backward compatible with accounts that have no blocked subcollection.
Block documents and reports are new user data and must be included in account-deletion cleanup and aligned with the privacy policy and App Store privacy declarations.
The moderation queue is intentionally write-only to clients, so captain review requires existing trusted console or Admin SDK access.
Rollback of the app leaves server documents inert but does not delete blocks or reports.
No feature flag is required because hiding a blocked identity is account-scoped and the new paths are additive.

## Human gates

- Firebase deployment and App Store submission remain with the captain or release workflow.

## Published support evidence

- In-app support is reachable from Account > Support > Contact Us in `AscendApp/Features/Account/Views/AccountView.swift`, which navigates to the existing feedback forms in `AscendApp/Features/Account/Views/ContactUs/ContactUsView.swift`.
- The App Store product-page package sets the Support URL to `https://ascendstepper.com/support` in `data/ascend-support-page-and-product-page-package/app-store-copy.md`.
- Both the public support URL and its production Firebase Hosting URL returned HTTP 200 during implementation verification on July 29, 2026.
