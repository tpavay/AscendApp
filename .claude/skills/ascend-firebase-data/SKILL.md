---
name: ascend-firebase-data
description: Use when adding, renaming, or removing any Firestore field - including from a Swift model or repository, which requires a matching firestore.rules update first - and when changing security rules or indexes, writing user media to Firebase Storage, deleting an account or sweeping its data, or handling offline/connectivity state in Ascend - and when reading any of these shapes back, because split buckets, user-scoped climbs, and collection listings each misreport as empty. Covers the strict hasOnly/hasAll rules contract, the required rules-first change order, the server-enforced paid-access predicate and what stays open before purchase, user-scoped Storage prefixes, the account-deletion ordering contract, the single-source-of-truth connectivity rule, and how to query these paths without reading data that is there as data that is missing.
---

# Ascend Firestore + Storage

Load the `vibe-security` skill for any auth/authz/trust-boundary change, and `firebase-firestore-standard` for rules and query design.

Before any claim about what a database *already holds* - whether a backfill is needed, whether a collection has rows, whether production is affected - use `ascend-data-investigation` and read the database. Never infer it, recall it, or take it from a document; production has held real climbers' data since the App Store launch, and `docs/production-backend-rollout-runbook.md` is the single owner of that fact.

## Schema changes (rules first - writes are rejected server-side otherwise)

`firestore.rules` uses strict `hasOnly` + `hasAll` field validation on every client-writable collection. Adding, removing, or renaming a field in the app **requires a matching update to `firestore.rules`** - otherwise writes will be rejected at the server.

Server-owned collections are the exception: they are `allow write: if false` and validate no fields, because no client can write them at all. Adding a field to one (for example the `live_replay_leaderboards` subtree, written only by Cloud Functions and Admin SDK scripts) needs no rules change.

A *new* top-level server-owned collection still needs its own `allow read, write: if false` match. The checked-in top-level matches are also the reviewed deletion contract for dev/staging resets, so an undeclared one blocks `npm run db:wipe` fail-closed - see `ascend-dev-fixtures`.

## Which collections must be server-owned

**Shape validation is not evidence validation.** A rule can prove a document has the right fields, the right types, and the right author, and still have no idea whether the numbers in it happened. Decide by what reads the document, not by who writes it:

- If a scheduled job, a counter, or an award reads a field, that collection is **server-write-only** and derived from the canonical records. `leaderboard_stats` was the counter-example: rules validated its shape and bound its identity to the publisher's own profile, yet a signed-in climber could `PATCH` `totalSteps: 2000000000`, hold every board, and have the nightly finalizer freeze permanent achievements from it (#307). A forged permanent award is data surgery to unwind, not a code fix.
- The derivation reads the private canonical record - `users/{uid}/workouts` for standings - and writes the projection through the Admin SDK, which bypasses rules. One derivation, called by every trigger and by the backfill script; never a per-trigger copy.
- **Deriving is not verifying.** The canonical records are still client-authored, and Ascend has no App Check and no server-side sensor ingestion, so the server's own evidence is only as good as the device that produced it. Bound what you derive by what is physically possible (see `ascend-leaderboards` for the standings envelope) and say plainly that the remainder is open. Claiming a derived number is "verified" is how a known gap becomes an assumed guarantee.
- A seeded fixture row in a server-owned collection needs a synthetic marker (`isSynthetic: true`), or the derivation will delete it for having no evidence behind it. See `ascend-dev-fixtures`.

When changing Firestore document schemas, always update in this order:
1. Update `firestore.rules` to allow the new/changed fields
2. Update the Swift model + write logic
3. Deploy rules to all environments before or alongside the app update

The same `firestore.rules` file must be deployed to all environments (dev, staging, production) to catch schema mismatches early. Never test against loose rules in dev while production has strict ones.

Verify with `npm run test:firebase-rules` (emulator-backed rules tests under `tests/firebase-rules/`).
CI runs the same command on any PR touching rules, indexes, or Firebase config - see `ascend-deploy` for that job.

That command pins `--test-concurrency=1`, and the files must keep running one at a time.
The Storage emulator holds exactly one global ruleset - `PUT /internal/setRules` takes no project - so each file's `initializeTestEnvironment` replaces the ruleset every other file is using.
While the swap is in flight the emulator answers *every* storage request with a blanket 403 that skips the auth check entirely, so a parallel run both fails owner-only setup like `clearStorage()` and turns `assertFails` assertions green for the wrong reason.
Giving each file its own `projectId` does not help; the buckets are separate but the ruleset is not.

## Paid access is a rules predicate, not a screen

The paywall is enforced at the backend boundary: `firestore.rules` and `storage.rules` require `users/{uid}/entitlements/app_access` to exist, and only the RevenueCat webhook and its reconciliation callable can create it.
`docs/revenuecat-server-entitlement-enforcement.md` owns that system - the webhook contract, the vendor setup, the choke-point list, and the deploy ordering that keeps a missing secret from locking subscribers out.
What matters while editing rules:

- Gate by operation, not by collection.
  `isPaidOwner(userId)` / `hasPaidAppAccess()` guards create and update on the paid product, another climber's copy of a public projection, shared paid content like global leaderboards and replay indexes, and the object bytes of workout media in Storage.
  The per-collection choke-point list lives in the doc named above; read it there rather than inferring it from a summary here.
- Keep `isOwner(userId)` for deletes and for everything that has to work before purchase and after lapse - onboarding, auth, restore, account management, support and safety, identity publication, and account deletion.
  That carve-out covers enumerating an owner's own data, not just deleting it.
  Account deletion sweeps a collection by listing it and deleting what comes back, and Firestore evaluates a list rule against the query rather than against the stored documents, so a paid read gate refuses an unentitled owner's sweep even when the collection is empty.
  Read on `users/{uid}/workouts`, `routines`, and `routine_folders` and `list` on the `users/{uid}` Storage media prefixes therefore match their owner-gated delete, while `profile_workouts` adds the owner to its paid read gate instead of replacing it.
  Re-tightening any of those to `isPaidOwner` reintroduces a guideline 5.1.1(v) deletion blocker; `tests/firebase-rules/account-deletion-contract.test.mjs` is the suite that catches it.
  Paid enforcement must never trap a user's data or their exit.
- `climb-images/` and the Hosting climb catalog deliberately stay open to any signed-in caller: the `firstClimb` onboarding stage runs before the paywall and renders that artwork.
- `entitlements`, `entitlement_status`, and `entitlement_reconciliations` are `allow read, write: if false`.
  A client that could write any of them could mint its own paid access or defeat the reconciliation cooldown.
- The paid predicate costs one document access per Firestore request, and one *billable cross-service Firestore read* per Storage request.
  The Storage side also depends on the Firebase Storage service account holding `Firebase Rules Firestore Service Agent`; remove that role and Storage fails closed.

## Schema versions are ranges in the rules, never equalities

`schemaVersion` and `objectSchemaVersion` go through `isSupportedSchemaVersion`, which accepts a bounded range rather than one exact number.
Never write `schemaVersion == <n>` into a rule, and never require an incoming version to equal the stored one.
Rules deploy globally and instantly while app rollout is gradual, so an exact pin locks out in both directions the day the number moves: stored documents at the old number stop being updatable by an updated client, and clients still on the old build stop being able to write at all.
The number carries no authority - every field is validated by type and domain independently of it, which is what actually protects the data.
The workout update rule lets the stored version move forward but not backward, because whole-document `setData` would otherwise let an older build drop the fields a newer schema added.

`identityPolicyVersion` is deliberately not one of these: it asserts which moderation policy screened a display name, so accepting an older value would accept weaker screening.

Bumping a version then needs no rules edit at all - it is a Swift-constant change. Verify with the schema-version range tests in `tests/firebase-rules/workout-contract.test.mjs`.
The rules being permissive does not make every bump free on the client: the heart-rate sidecar blob version is still matched exactly by `WorkoutHeartRateSidecarValidator`, so bumping it makes already-uploaded sidecars unrestorable unless the validator learns to read the older shape - see `ascend-workout-model`.

## The workout write rule has almost no expression budget left

Firestore aborts rule evaluation at 1000 expressions and returns a plain `PERMISSION_DENIED`, so an over-budget document silently never reaches the cloud backup.
That is not hypothetical: the workout rule outgrew the budget and refused one climber's Live Climb for four days, indistinguishably from a deliberate denial (ASCEND-IOS-1J, issue #295).
Rules functions inline their arguments, so each `item.` dereference inside a per-element validator re-evaluates the whole `request.resource.data.<list>[i]` chain - the cost scales with the number of distinct field references per element, not with the number of comparisons.
Enum validators there take their value untyped on purpose: membership in a list of string literals already excludes non-strings, so a preceding `is string` is a no-op the budget cannot afford.

**Hoist every repeated subexpression.** Because arguments are inlined, a validator that re-derives `request.resource.data.keys()` or `list.size()` pays for that derivation on every branch mentioning it - `keys()` alone was being recomputed once per optional workout field.
`isValidWorkoutDocument` therefore binds the payload and its key set once with `let`, and the per-element validators take the element's key set and the list's size as parameters, so neither is ever re-derived.
A validator that takes a hoisted parameter must be *called* with it everywhere: the routine rule kept calling `isValidWorkoutWeightConfiguration` with one argument after it grew a second, which the emulator reports as an evaluation error inside a bare `PERMISSION_DENIED` - so a routine carrying default weights simply stopped backing up.
Adding the paid check to that path was affordable for the same reason: `isPaidOwner` replaced the signed-in half of the old owner predicate with the grant lookup instead of adding a third term.

**Measure before adding anything to that path.** `tests/firebase-rules/workout-expression-budget.test.mjs` exercises every declared cap against a fully-populated document, so a check that no longer fits fails there rather than in the field. Single-element fixtures prove nothing.

Two rules the recovery left behind, both in the rule's own header comment - read it before editing:

- **The rule enforces authorization and the trust boundary, not owner-private hygiene.** A workout document is read by its owner and by Cloud Functions. What stays checked: ownership, canonical identity, the strict `hasOnly`/`hasAll` key contract, bounded list sizes, the Storage path binding on the heart-rate sidecar, `startedAt`'s type, the participation fields a function trusts as written, and the physical envelope below. What went: scalar ranges, string lengths, media and weight-entry internals, timestamp ordering. The test for dropping a field's type check is not "a function reads it" - it is whether that function *rejects* what it reads (fail-closed, so the rule need not) or *coerces* it (so the rule is the only guard).
- **`steps` and `durationSeconds` are the exception that check does not cover, and `isPhysicallyPossibleClimb` is why.** Both are well-typed and fail-closed downstream, so the rejects/coerces test would drop them - but `leaderboardStats` derives every global standing from them as written and `finalizeLeaderboardAchievements` freezes that order into permanent awards, and there is no App Check attestation, so a paying account can POST a fabricated climb with the app closed. Their *range* is a trust boundary even though their *type* is not. The bounds are 4 steps/second, 120,000 steps per submission, five days of duration, and `startedAt` no more than a day ahead of `request.time`; each one is deliberately far looser than the 220/min and 24h filters `leaderboardStats` applies, because a refused write is a climb that can never back up while a filtered one just does not score. `tests/firebase-rules/workout-physical-envelope.test.mjs` pins both halves.
- **A declared cap must never exceed the client constant that enforces it.** The rule declared eight participations, could evaluate one, and the client emitted however many the workout had. `WorkoutRemoteSyncLimits` now mirrors the rule by hand; changing a number means changing both and re-running the budget test in the same change.

**Measured, so nobody has to re-derive it.** The user-routine rule (issue #304) was benchmarked against the emulator with a real document: a full per-element validator - `hasOnly`/`hasAll` plus ten typed fields - fits **two** list elements; narrowed to four typed fields it fits **eleven**; `item is map` alone fits **twenty-four**.
That is the whole budget, for one list, in a rule with about twenty other scalar checks.
So a user-authored list of unbounded length simply cannot be validated element by element, and pretending otherwise ships a rule that silently rejects the largest documents.
When that is where you land, say so in the rule with the numbers, validate what the document-level `hasOnly`/`hasAll` can reach, bound the list size, and move element validation into the client's decoder - `users/{uid}/routines` is the worked example.
The asymmetry that makes it acceptable there and not for workouts: nothing but the owner reads a routine, while a workout's `participations` are read and trusted by the Cloud Functions that publish leaderboard rows.

## Reading these shapes back

`ascend-data-investigation` owns the *method*: the absence rule, `scripts/firestore-query.mjs`, and the four outcomes it refuses to collapse.
Read it before answering any question about what a database holds.
This section owns what the *shapes defined here* do to a reader who queries them the obvious way, because three of them report as "nothing is there" while the data sits one path segment below.

Every number below was read from staging (`ascend-staging-fa7d5`) on 2026-08-26.
They are illustrations of a shape, not standing counts: re-read before quoting one.

### A document that is only a parent is invisible to a collection listing

`live_replay_leaderboards/{contextKey}/splitBuckets/{index}` is never written as a document.
The publisher (`entriesCollectionReference` in `functions/src/liveReplayLeaderboard.ts`) and `seed-demo-user.mjs` both address `splitBuckets/{index}/entries` directly, and Firestore materializes the missing ancestor implicitly rather than creating it.
The app reads it the same way and never lists the collection - `FirestoreLiveReplayLeaderboardRepository.entriesCollection(context:bucketIndex:)`.

On `live_climb__empire-state-building` that gives five different answers to what looks like one question:

| Read | Result |
|---|---|
| `splitBuckets` collection `.get()` | 0 documents, `empty: true` |
| `splitBuckets` `.count()` aggregation | 0 |
| `splitBuckets` `.listDocuments()` | 232 references |
| `splitBuckets/0` `.get()` | `exists: false`, no fields |
| `splitBuckets/0/entries` `.count()` | 4 |

Zero is the correct answer to what a collection query asks and the wrong answer to "does this climb have replay data".
Answering the second question with the first is what produced "zero split buckets anywhere" on 2026-08-26, while 232 buckets of entries sat under that one context.

Ask the paths instead:

```bash
node scripts/firestore-query.mjs subcollections \
  live_replay_leaderboards/live_climb__empire-state-building \
  --env staging --expect finishers,splitBuckets,completionSnapshots
#   listed: completionSnapshots, finishers, splitBuckets, userBestAttempts
#   direct probe .../finishers: 85
#   direct probe .../splitBuckets: 232 (all 232 are subcollection parents)
#   direct probe .../completionSnapshots: 4

node scripts/firestore-query.mjs count \
  live_replay_leaderboards/live_climb__empire-state-building/splitBuckets/0/entries --env staging
#   matches: 4
```

`count` and `list` fall back to `listDocuments` and name the phantom parents in their output; an aggregation query written by hand reports 0 and says nothing.
The context document's own `replayEntryCount`, `totalClimbers`, `completedCount` and `seedBucketCount` are a publisher-written summary - useful as a second opinion that agrees or disagrees with the paths, never as the count itself.

### A climb lives under its climber, so no top-level collection counts it

Staging has 12 root collections and none of them is `workouts` or `climb_completions`; both come back `EMPTY (verified)` against a control that returned 20.
Every climb, projection, and award is user-scoped, which is what makes the owner predicates in the rules above expressible at all:

```
users/{uid}/workouts · profile_workouts · achievements · profile_stats · public_profile
```

That is also exactly where `scripts/seed-demo-user.mjs` writes.
Counting a root collection therefore reports a successful seed as a failed one:

```bash
node scripts/firestore-query.mjs count users/<uid>/workouts --env staging   # matches: 12
node scripts/firestore-query.mjs count workouts --env staging               # EMPTY (verified) - no such collection
```

The top-level collections a climb does reach - `leaderboard_stats`, `live_replay_leaderboards`, `live_climb_community_stats` - hold server-derived aggregates keyed by climber-period or by context, never one row per climb.

### `(none)` from a collection listing settles nothing

`listCollectionIds`, and the `listCollections()` call over it, answers correctly today: against that same context document it returns `completionSnapshots, finishers, splitBuckets, userBestAttempts` through the REST endpoint, the Admin SDK, and the Firebase MCP tool alike.
A `(none)` from it is therefore a claim about the *call*, not about the database, and the call is easy to break into silence - `ascend-data-investigation` carries the reproduced mechanisms.
Never treat a negative listing as evidence here.
Probe the subcollections you expect by name (`subcollections <doc> --expect a,b,c`), which counts each path itself and cannot be talked out of a positive.

### `firestore.rules` is a path map, not an inventory

Every collection a *client* touches has a `match` block, which makes the rules file the best navigation map of the app's paths.
It is not a list of what exists.
A server-owned subcollection written only through the Admin SDK needs no rule at all, so it is absent from the file and unreadable by any client: `live_replay_leaderboards/{contextKey}/userBestAttempts` is written by `liveReplayLeaderboard.ts` and by the seed, exists in staging, and appears nowhere in `firestore.rules`.
Discover paths from the database, then confirm the client-facing contract in the rules - not the other way round.

## Storage pathing + rules

User-generated media must be stored under user-scoped prefixes:
- `users/{uid}/photos/...`
- `users/{uid}/videos/...`
- `users/{uid}/profile_pictures/...`
- `users/{uid}/workout_heart_rate/...`

Rules:
- Never write user media to shared root paths. `photos/`, `videos/`, and `profile_pictures/` at the bucket root are closed to every client (`read, write: if false`) and must stay that way: a flat path carries no owner segment, so any rule permissive enough to admit the owner admits every signed-in account. Objects predating the user-scoped migration still sit there, unattributable and reachable only by the backend.
- Server-owned synthetic Live Replay avatar fixtures may live under `live-replay-avatars/{seedPackId}/...`; they are not user media, should be read-only to clients, and must be written only by admin/server tooling.
- Legacy share card template assets may still live under `share-card-templates/...`, but workout share cards in v1 must not fetch their backgrounds or layout config from Firebase.
- Account deletion and cleanup should target only the authenticated user's scoped prefixes, including durable workout heart-rate sidecars and private workout backup documents.

## Account deletion (Apple 5.1.1(v))

Ordering is the whole game. Every delete in `firestore.rules` is gated on `isOwner(userId)`, so anything still present when `user.delete()` succeeds is orphaned forever - no client can authenticate as that uid again.
`AccountDeletionService` therefore re-authenticates, revokes the Apple token, deletes all remote data, then deletes the auth user last. Its ordering is locked in by `AscendAppTests/AccountDeletionServiceTests.swift`; if you add a remote record, add its deletion before the auth step and extend those tests.

- Firebase calls live behind `AccountDeletionGateway`, and on-device cleanup behind `AccountDeletionLocalCleanup`, so the sequence is testable and tests never touch the host's UserDefaults.
- **Quiescing the device is part of the ordering, not a cleanup detail.**
  Right after re-auth and before the first destructive step, deletion suspends and drains every writer of account-scoped local state through `AuthenticatedBootstrapCoordinator.suspendAndDrain`: the one bootstrap chain plus the autonomous `AuthenticatedSessionWorker`s listed in `AutonomousSessionWorkers.all` (`AppleHealthEnrichmentService`, `MediaUploadManager`) that a drain alone cannot reach, because an enrichment pass or an upload retry starts on its own schedule.
  That list is shared with sign-out, which stops the same workers through `endAuthenticatedSession` - a worker registered in one place is covered at both ends of a session.
  Draining only stops what already started, so `isSuspended` stays raised for the whole flow and those workers refuse to begin a new pass while it is - that refusal is the second half of the guarantee, not a redundancy.
  The drain is bounded by `AuthenticatedBootstrapCoordinator.drainTimeout` and is safe to time out, and a timeout is recorded as both a diagnostic and a non-fatal under `authenticated_session_drain_timed_out` because the UserDefaults ring buffer that would otherwise hold it is wiped two steps later.
- **A deletion that stops short of `user.delete()` resumes the suspended work; one that gets past it discards it.**
  Anything still running afterwards would write the deleted uid's rows back into a store that has just been emptied, and the sign-in ownership gate then correctly blocks the replacement account with the full-screen data-mismatch wall (#389).
  Fix the source state and the lifecycle when that wall appears - never weaken the gate, which is the only thing protecting a different climber's unsynced work.
- **Clearing the persistent domain is not clearing the settings.**
  `SettingsManager.shared` is process memory that survives `removePersistentDomain`, so deletion also calls `SettingsManager.resetInMemoryAfterAccountDeletion()`; without it a same-session re-signup inherits the deleted account's units, fitness level, and base-level onboarding state.
  That reset deliberately suppresses its own `didSet` writes so it cannot repopulate the domain deletion just cleared.
  Coverage: `AscendAppTests/AccountDeletionSessionWorkGateTests.swift`, `AccountDeletionSettingsTests.swift`, `AuthenticatedBootstrapCoordinatorTests.swift`.
- Deleting a Sign in with Apple account must revoke the Apple token via `Auth.auth().revokeToken(withAuthorizationCode:)`, immediately after re-auth rather than just before `user.delete()`: the authorization code expires in about five minutes and the sweeps in between can outlast that window, so revoking later can silently no-op. The code is single-use and is captured during re-auth by `AuthenticationService.reauthenticateWithApple()`, which is the only place it is available. Revocation is deliberately best-effort: failing to delete is a worse guideline violation than a lingering token.
- Re-authentication prefers Apple whenever `apple.com` is linked, even alongside another provider. Firebase's "link accounts that use the same email" setting puts several providers on one uid, and only an Apple authorization yields the code revocation needs, so any other choice silently skips revocation. `AccountDeletionReauthenticationProvider.preferred(forProviderIDs:)` owns that decision so it stays unit-testable.
- Clients can only delete what the rules allow. Server-owned subcollections (`achievements`, `lifecycle`, `lifecycle_events`, `communication_preferences`, `notification_devices`, `integrations`, `liveClimbPublishStatuses`, and the entitlement projections above) are closed to every client and are unreachable from one.
- The `cleanupDeletedUserData` Cloud Function (`functions/src/accountCleanup.ts`) is the authoritative sweep, not just a safety net. It triggers on delete of `users/{uid}`, discovers subcollections via `listCollections()` rather than a hardcoded list, and retries on failure.
- Discovery only reaches the `users/{uid}` subtree.
  User-keyed data stored outside it needs an explicit step in the sweep - top-level collections, the collection-group replay `entries`, another user's `blocked` subcollection holding the deleted uid, and denormalized fields such as `firstAscent*` all qualify.
  The `cleanupDeletedUserData` doc comment in `functions/src/accountCleanup.ts` is the authoritative step list; read it rather than trusting a copy.
  Add a step whenever a new collection denormalizes a user's display fields, delivery tokens, email, or safety context.
- `feedback` is hard-deleted, not anonymized. Its `message` is free text the user typed, so it can hold anything they chose to disclose and stripping `userEmail` alone would not make it anonymous. The report is not lost: `onFeedbackCreated` already emails it to the admin inbox, which is a support record rather than a user-data store.
- A First Ascent is de-identified, not deleted. The slot can never be reclaimed, so the claim itself outlives the account: `firstAscentCompletedAt`, `firstAscentWorkoutId`, and `firstAscentUserId` stay, while `firstAscentDisplayName` becomes `Anonymous Climber`, `firstAscentPhotoURL` and `firstAscentAvatarToken` are cleared, and `firstAscentIsSynthetic` is forced to `false` so the record can never pass for a preserved fixture identity. The uid is kept on purpose - it resolves to nobody once `users/{uid}` and the auth user are gone, and the client still reads it to decide whether the viewer holds the slot. Aggregate `completedCount` is untouched, because decrementing it could reassign a permanent finisher order.
- Replay entries are de-identified rather than deleted so ranks, steps, times, and race history remain stable.
  Account cleanup queries the `entries` collection group by `userId`, sets `displayName` to `Anonymous Climber`, clears `avatarToken` and `photoURL`, sets `identityState` to `deleted`, and forces `isSynthetic` to `false` while leaving every competitive field unchanged.

## Connectivity UX
- Connectivity is an app-wide concern with a single source of truth - features must not each implement their own offline detection.
- Surface connectivity state in one consistent, persistent location (not feature-by-feature banners or alerts). When the user is offline, they should know it without having to discover it through failed actions.
- Fail fast on user-initiated network actions when there is no network path - don't wait for request timeouts to tell the user they're offline.
- Connectivity is *not* the same as request success. Online requests can still time out, hit backend errors, or return partial data. Features decide the user-facing response (retry button, cache fallback, error message), but the mechanics - timeout policy, retry logic, error categorization - belong in shared request infrastructure. If you find yourself implementing the same network error pattern in a second feature, extract it into the shared layer rather than duplicating it.

## Related
- Firestore has no fixed shape, so a field change here is *not* a data migration; the local SwiftData store is the one that needs versions and stages, and `ascend-data-migration` covers it.
- Adding a Firestore field usually also means declaring a new collected data type - see `ascend-privacy-manifest`.
- Private workout backups are private; public surfaces use separate public data models. See `ascend-workout-model`.
