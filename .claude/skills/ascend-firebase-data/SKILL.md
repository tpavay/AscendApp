---
name: ascend-firebase-data
description: Use when adding, renaming, or removing any Firestore field - including from a Swift model or repository, which requires a matching firestore.rules update first - and when changing security rules or indexes, writing user media to Firebase Storage, deleting an account or sweeping its data, or handling offline/connectivity state in Ascend. Covers the strict hasOnly/hasAll rules contract, the required rules-first change order, user-scoped Storage prefixes, the account-deletion ordering contract, and the single-source-of-truth connectivity rule.
---

# Ascend Firestore + Storage

Load the `vibe-security` skill for any auth/authz/trust-boundary change, and `firebase-firestore-standard` for rules and query design.

## Schema changes (rules first - writes are rejected server-side otherwise)

`firestore.rules` uses strict `hasOnly` + `hasAll` field validation on every client-writable collection. Adding, removing, or renaming a field in the app **requires a matching update to `firestore.rules`** - otherwise writes will be rejected at the server.

Server-owned collections are the exception: they are `allow write: if false` and validate no fields, because no client can write them at all. Adding a field to one (for example the `live_replay_leaderboards` subtree, written only by Cloud Functions and Admin SDK scripts) needs no rules change.

When changing Firestore document schemas, always update in this order:
1. Update `firestore.rules` to allow the new/changed fields
2. Update the Swift model + write logic
3. Deploy rules to all environments before or alongside the app update

The same `firestore.rules` file must be deployed to all environments (dev, staging, production) to catch schema mismatches early. Never test against loose rules in dev while production has strict ones.

Verify with `npm run test:firebase-rules` (emulator-backed rules tests under `tests/firebase-rules/`).
CI runs the same command on any PR touching rules, indexes, or Firebase config - see `ascend-deploy` for that job.

## Schema versions are ranges in the rules, never equalities

`schemaVersion` and `objectSchemaVersion` go through `isSupportedSchemaVersion`, which accepts a bounded range rather than one exact number.
Never write `schemaVersion == <n>` into a rule, and never require an incoming version to equal the stored one.
Rules deploy globally and instantly while app rollout is gradual, so an exact pin locks out in both directions the day the number moves: stored documents at the old number stop being updatable by an updated client, and clients still on the old build stop being able to write at all.
The number carries no authority - every field is validated by type and domain independently of it, which is what actually protects the data.
The workout update rule lets the stored version move forward but not backward, because whole-document `setData` would otherwise let an older build drop the fields a newer schema added.

`identityPolicyVersion` is deliberately not one of these: it asserts which moderation policy screened a display name, so accepting an older value would accept weaker screening.

Bumping a version is then a Swift-constant change alone. Verify with the schema-version range tests in `tests/firebase-rules/workout-contract.test.mjs`.

## The workout write rule has almost no expression budget left

Firestore aborts rule evaluation at 1000 expressions and returns a plain `PERMISSION_DENIED`, so an over-budget document silently never reaches the cloud backup.
Rules functions inline their arguments, so each `item.` dereference inside a per-element validator re-evaluates the whole `request.resource.data.<list>[i]` chain - the cost scales with the number of distinct field references per element, not with the number of comparisons.
The workout rule is already over budget well below its own declared list caps (issue #295), so before adding any check to that path, exercise it against a document with several nested list elements rather than the single-element fixtures.
Enum validators there take their value untyped on purpose: membership in a list of string literals already excludes non-strings, so a preceding `is string` is a no-op the budget cannot afford.

## Storage pathing + rules

User-generated media must be stored under user-scoped prefixes:
- `users/{uid}/photos/...`
- `users/{uid}/videos/...`
- `users/{uid}/profile_pictures/...`
- `users/{uid}/workout_heart_rate/...`

Rules:
- Never write user media to shared root paths (`photos/`, `videos/`, `profile_pictures/`) in production.
- Server-owned synthetic Live Replay avatar fixtures may live under `live-replay-avatars/{seedPackId}/...`; they are not user media, should be read-only to clients, and must be written only by admin/server tooling.
- Legacy share card template assets may still live under `share-card-templates/...`, but workout share cards in v1 must not fetch their backgrounds or layout config from Firebase.
- Account deletion and cleanup should target only the authenticated user's scoped prefixes, including durable workout heart-rate sidecars and private workout backup documents.

## Account deletion (Apple 5.1.1(v))

Ordering is the whole game. Every delete in `firestore.rules` is gated on `isOwner(userId)`, so anything still present when `user.delete()` succeeds is orphaned forever - no client can authenticate as that uid again.
`AccountDeletionService` therefore re-authenticates, revokes the Apple token, deletes all remote data, then deletes the auth user last. Its ordering is locked in by `AscendAppTests/AccountDeletionServiceTests.swift`; if you add a remote record, add its deletion before the auth step and extend those tests.

- Firebase calls live behind `AccountDeletionGateway`, and on-device cleanup behind `AccountDeletionLocalCleanup`, so the sequence is testable and tests never touch the host's UserDefaults.
- Deleting a Sign in with Apple account must revoke the Apple token via `Auth.auth().revokeToken(withAuthorizationCode:)`, immediately after re-auth rather than just before `user.delete()`: the authorization code expires in about five minutes and the sweeps in between can outlast that window, so revoking later can silently no-op. The code is single-use and is captured during re-auth by `AuthenticationService.reauthenticateWithApple()`, which is the only place it is available. Revocation is deliberately best-effort: failing to delete is a worse guideline violation than a lingering token.
- Re-authentication prefers Apple whenever `apple.com` is linked, even alongside another provider. Firebase's "link accounts that use the same email" setting puts several providers on one uid, and only an Apple authorization yields the code revocation needs, so any other choice silently skips revocation. `AccountDeletionReauthenticationProvider.preferred(forProviderIDs:)` owns that decision so it stays unit-testable.
- Clients can only delete what the rules allow. Server-owned subcollections (`achievements`, `lifecycle`, `lifecycle_events`, `communication_preferences`, `notification_devices`, `integrations`, `liveClimbPublishStatuses`) are `allow write: if false` and are unreachable from any client.
- The `cleanupDeletedUserData` Cloud Function (`functions/src/accountCleanup.ts`) is the authoritative sweep, not just a safety net. It triggers on delete of `users/{uid}`, discovers subcollections via `listCollections()` rather than a hardcoded list, and retries on failure.
- Discovery only reaches the `users/{uid}` subtree.
  User-keyed data stored outside it needs an explicit step in the sweep - top-level collections, the collection-group replay `entries`, another user's `blocked` subcollection holding the deleted uid, and denormalized fields such as `firstAscent*` all qualify.
  The `cleanupDeletedUserData` doc comment in `functions/src/accountCleanup.ts` is the authoritative step list; read it rather than trusting a copy.
  Add a step whenever a new collection denormalizes a user's display fields, delivery tokens, email, or safety context.
- `feedback` is hard-deleted, not anonymized. Its `message` is free text the user typed, so it can hold anything they chose to disclose and stripping `userEmail` alone would not make it anonymous. The report is not lost: `onFeedbackCreated` already emails it to the admin inbox, which is a support record rather than a user-data store.
- A First Ascent is de-identified, not deleted. The slot can never be reclaimed, so the claim itself outlives the account: `firstAscentCompletedAt`, `firstAscentWorkoutId`, and `firstAscentUserId` stay, while `firstAscentDisplayName` becomes `Anonymous Climber`, `firstAscentPhotoURL` and `firstAscentAvatarToken` are cleared, and `firstAscentIsSynthetic` is forced to `false` so the record can never pass for a preserved fixture identity. The uid is kept on purpose - it resolves to nobody once `users/{uid}` and the auth user are gone, and the client still reads it to decide whether the viewer holds the slot. Aggregate `completedCount` is untouched, because decrementing it could reassign a permanent finisher order.
- Replay entries are de-identified rather than deleted so ranks, steps, times, and race history remain stable.
  Account cleanup queries the `entries` collection group by `userId`, sets `displayName` to `Anonymous Climber`, clears `avatarToken` and `photoURL`, sets `identityState` to `deleted`, and forces `isSynthetic` to `false` while leaving every competitive field unchanged.
- Waitlist-welcome `email_jobs` deliberately outlive the account. They are keyed by email hash rather than uid and belong to the newsletter relationship, which has its own unsubscribe path and is neither granted nor revoked by owning an account.

## Connectivity UX
- Connectivity is an app-wide concern with a single source of truth - features must not each implement their own offline detection.
- Surface connectivity state in one consistent, persistent location (not feature-by-feature banners or alerts). When the user is offline, they should know it without having to discover it through failed actions.
- Fail fast on user-initiated network actions when there is no network path - don't wait for request timeouts to tell the user they're offline.
- Connectivity is *not* the same as request success. Online requests can still time out, hit backend errors, or return partial data. Features decide the user-facing response (retry button, cache fallback, error message), but the mechanics - timeout policy, retry logic, error categorization - belong in shared request infrastructure. If you find yourself implementing the same network error pattern in a second feature, extract it into the shared layer rather than duplicating it.

## Related
- Adding a Firestore field usually also means declaring a new collected data type - see `ascend-privacy-manifest`.
- Private workout backups are private; public surfaces use separate public data models. See `ascend-workout-model`.
