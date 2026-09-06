---
name: ascend-data-investigation
description: Use before answering any question about what is actually in a Firestore database or a Storage bucket - leftover data after a deletion, whether a leaderboard has entries, whether a user's climbs made it to the cloud, how many objects sit under a path, or "did this backfill run". Fires from bug triage, account-deletion work, release checks, and captain questions, none of which look like Firebase work. Covers the absence rule, the read-only query wrapper, and the traps that have produced confidently wrong answers.
---

# Investigating Ascend's Data

## Query production; never recall it

If anything could possibly concern production or the data in it, **read production**.
Do not infer it, do not remember it, and do not trust a document that states it - including this one.

Ascend has been live on the App Store since 2026-08-25, so `ascend-prod-9c8f2` accumulates real climbers' data continuously.
Any sentence shaped like "production is empty", "there is nothing to backfill", or "that collection has no rows" is a measurement with a timestamp, not a standing fact, and a stale one has already been used to justify skipping work that real user data requires.
`docs/production-backend-rollout-runbook.md` is the single owner of what production holds; a fresh read beats it.

The trap is that Firebase tooling answers for whichever project is currently **active**, and that is never production by default:
`.firebaserc` points `default` at the dev project, and an earlier task can leave staging selected.
Staging is full of QA and seeded accounts that look exactly like real climbers, so the likeliest wrong answer is a plausible one from the wrong database.
Confirm the active project before trusting anything, pass `--env` explicitly on every read, and name the environment in the answer.

## The absence rule

**Never report that data is absent until the same method has returned a positive result against data you already know is there.**

A query that fails and a query that finds nothing look identical from the outside.
Both print nothing.
On 2026-08-20/21 that one confusion produced six wrong answers in a single session: a nonexistent CLI subcommand printed generic help, a shell loop broke on the unquoted `(default)` database ID, a substring grep counted the wrong prefix, and each time the empty output was reported to the captain as an empty database.
A production leaderboard with 13 entries was reported as having none.
A production bucket holding 264 objects was reported as empty.

The recipe, every time:

1. Run your method against a path you have **independently confirmed holds data**.
2. Confirm it returns a positive number.
3. Only then run it against the target, and only then is a zero worth saying out loud.

The one check in that session that did not go wrong was the one where this was done first.
It exposed the bogus result immediately.

## Use the wrapper, do not hand-roll curl

`scripts/firestore-query.mjs` owns every mechanical trap: credential resolution, the `(default)` database ID, URL encoding, prefix anchoring, and the control probe above.
It is read-only by construction and tested to stay that way.

```bash
cd scripts && npm install        # once; firebase-admin
gcloud auth application-default login

node scripts/firestore-query.mjs collections --env dev
node scripts/firestore-query.mjs count users/<uid>/workouts --env staging
node scripts/firestore-query.mjs list live_replay_leaderboards --env dev --limit 5
node scripts/firestore-query.mjs get live_replay_leaderboards/live_climb__burj-khalifa --env dev
node scripts/firestore-query.mjs subcollections live_replay_leaderboards/live_climb__burj-khalifa \
  --env dev --expect finishers,splitBuckets,completionSnapshots
node scripts/firestore-query.mjs storage profile_pictures/ --env staging
node scripts/firestore-query.mjs count users --env prod --confirm-production
```

It reports exactly one of four outcomes and never collapses them:

| Outcome | Exit | Means |
|---|---|---|
| `FOUND` | 0 | The read completed and returned results. |
| `EMPTY (verified)` | 0 | Zero results, **and** the same method returned data at a control path. |
| `EMPTY (UNVERIFIED)` | 3 | Zero results, with nothing showing the method can see anything. Not an answer. |
| `FAILED` | 2 | The read did not complete. Says nothing about the path. Prints on stderr with no count. |

A control probe runs automatically on a zero result (`users` for Firestore, the bucket root for Storage).
Point it somewhere better with `--control <path>` when you know a more relevant populated path.
If you get `EMPTY (UNVERIFIED)`, you have not learned anything yet - fix the control and re-run.

## The traps

**`listCollectionIds` is not evidence of absence.**
The REST `:listCollectionIds` endpoint, and the `listCollections` call behind it, returned `none` for a document with three populated subcollections.
Treat a negative from it as no information.
Settle it by querying the expected paths directly: `subcollections <doc> --expect finishers,splitBuckets,completionSnapshots` counts each named path itself.

The endpoint itself is sound - re-verified on 2026-08-26 against staging, where it returns all four subcollections of `live_replay_leaderboards/live_climb__empire-state-building` via REST, the Admin SDK, and the Firebase MCP tool alike.
What breaks is the call, silently, and a hand-rolled `curl` gives two reproduced ways for that to happen:

```zsh
DOC="live_replay_leaderboards/live_climb__Empire-State-Building"
echo "$DOC:listCollectionIds"    # live_replay_leaderboards/live_climb__empire-state-buildingistCollectionIds
echo "${DOC}:listCollectionIds"  # correct
```

`:l` is a zsh modifier, so an unbraced expansion eats the `:l` and lowercases the path.
The URL then has no `:` verb left, which routes the POST to **`createDocument`** instead - a write attempt, which fails on parent validation and answers `INVALID_ARGUMENT` about a name that "lacks / at index 84", saying nothing about collections.
Brace every path variable.
And the database ID must survive intact: literal `(default)` and percent-encoded `%28default%29` both work, while a bare `default` answers `NOT_FOUND` - "The database default does not exist" - which reads like a missing database rather than a typo.

**A document that does not exist can still have data under it.**
Firestore keeps subcollections beneath a document that was never written.
`get` always reports the subcollections beneath the path for this reason.

**A collection of phantom parents counts as zero.**
`live_replay_leaderboards/<contextKey>/splitBuckets` returns a count of **0** on dev while `splitBuckets/0/entries` holds 59 rows, because the 361 bucket documents were never written as documents.
`count` and `list` fall back to `listDocuments` and say so; a hand-rolled count query will not.

**The Firebase console hides subcollections until a document is selected.**
"I looked and the document was empty" means nothing.
Deep-link to the document itself, path separators encoded as `~2F`:

```
https://console.firebase.google.com/project/<projectId>/firestore/databases/-default-/data/~2F<collection>~2F<docId>
```

The wrapper prints this link on every Firestore result.

**A Storage prefix anchors; a grep does not.**
`profile_pictures/` and `users/<uid>/profile_pictures/` are different places, and a substring match counts the second as the first - which is how six flat-path objects were reported as nineteen (issue #517).
The wrapper's `storage` command anchors server-side and re-checks every returned name.

**A successful read here does not mean a client could read it.**
The wrapper uses admin credentials, which bypass `firestore.rules` entirely.
Questions about what a *user* can reach are answered by the emulator-backed rules tests in `tests/firebase-rules/`, never by this tool.

## Emulator first

Routine work goes against the Local Emulator Suite.
Start it and run the wrapper with **no** `--env`; it reads the emulator by default whenever one is listening:

```bash
npx -y firebase-tools@15.22.1 emulators:start --project demo-ascendapp --only firestore
node scripts/firestore-query.mjs collections
```

An explicit `--env` always means the real backend, even with an emulator running.
`--env prod` additionally requires `--confirm-production`.

## Environments, and why a finding does not travel

| Alias | Project | Notes |
|---|---|---|
| `dev` | `ascend-f2e4f` | Seeded fixtures (`ascend-dev-fixtures`). Also the `.firebaserc` `default`. |
| `staging` | `ascend-staging-fa7d5` | TestFlight traffic plus QA and seeded accounts that look exactly like real climbers. |
| `prod` | `ascend-prod-9c8f2` | Real climbers, live on the App Store since 2026-08-25. Needs `--confirm-production`. |

Confirm which project the tooling is pointed at before reading anything, because none of these commands defaults to production:

```bash
npx -y firebase-tools@15.22.1 use          # prints the active alias/project
```

Identifiers differ per environment, so a document ID, a product ID or a count from one says nothing about another.
Staging subscription products are `ascend_staging_yearly` / `ascend_staging_monthly`; production is `ascend_yearly` / `ascend_monthly` (`docs/superwall-paywall-setup.md` is the authority).
Always name the environment in the answer; the wrapper prints it on every line.

## Where things live

`firestore.rules` is the authoritative path map - every collection the app has is a `match` block there.
This is a navigation map, not a schema.

Under `users/{uid}/`:

- `workouts/{workoutId}` - the cloud backup of a climb (`ascend-workout-model`).
- `landmarkResults/{landmarkId}` - per-landmark bests.
- `liveClimbPublishStatuses/{workoutId}` - whether a climb reached the leaderboards.
- `public_profile/`, `profile_stats/`, `profile_workouts/`, `achievements/` - server-derived public projections (`ascend-profile`).
- `entitlement_status/`, `entitlements/` - the server-owned paid grant (`docs/revenuecat-server-entitlement-enforcement.md`).

Live Replay leaderboards decompose per context, where `contextKey` is `live_climb__<climbId>` or `just_climb__global`:

```
live_replay_leaderboards/{contextKey}                    <- context summary, first ascent
  splitBuckets/{bucketIndex}/entries/{entryId}           <- the ranked rows; buckets are phantom parents
  finishers/{userId}                                     <- one row per climber who completed
  completionSnapshots/{workoutId}                        <- immutable rank at completion
```

Storage objects live under `users/{uid}/...` prefixes (`photos`, `videos`, `workout_heart_rate`, `profile_pictures`) plus the shared `climb-images/`, `share-card-templates/` and `live-replay-avatars/` trees; `storage.rules` is the authority, and the flat `photos/`, `videos/`, `profile_pictures/` roots are legacy.

## Before you answer

- [ ] Is this a claim about production? Then did you *read* production, rather than recall it or quote a document?
- [ ] Did the method return a positive result somewhere before you claimed a zero?
- [ ] Did you confirm which project was active, and did you name the environment?
- [ ] Did any command exit non-zero, or print `FAILED` or `UNVERIFIED`?
- [ ] If the answer is "nothing is there", did you check for subcollections and phantom parents beneath it?
