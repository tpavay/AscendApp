# Staging content capture

How to put staging into a known, believable state so App Store screenshots, video and marketing can be captured without performing every climb by hand.

## The command

```bash
cd scripts && npm install                 # once
gcloud auth application-default login     # once

node scripts/seed-content-ready.mjs --email you@example.com --dry-run
node scripts/seed-content-ready.mjs --email you@example.com
```

The account has to exist in staging's Firebase Auth already - sign into the staging build once with it, then run this.
Nothing creates accounts, and nothing touches any account but the one named.

Everything is idempotent.
Running it twice leaves the same state rather than doubling anything: every document it writes has an id derived from the account and the fixture entity, never from the run.
Dates do move forward on each run, which is the point - it is what keeps the newest session looking recent.

`--dry-run` prints every step's plan and writes nothing.
`--project dev` rehearses the same recipe against dev.
Production is refused before anything initializes, and there is no flag that changes that.

## How long it takes, and how you can tell it is alive

A warm run - staging already holds this seed's content, nothing in the fixtures changed - takes about **36 seconds** end to end.

A cold run takes about **three minutes**, and a cold run is the exception: it happens when the environment is empty, or when a fixture change means the boards really do have to be rewritten.
There are 520,784 split-bucket rows behind the replay boards - one document per synthetic climber per ten-second bucket - and Firestore accepts them at around 3,000 a second once every field on them is indexed.

The difference is a fingerprint.
Each board's summary carries a hash of the rows it holds (`seedRowFingerprint`), stamped only after those rows land.
A board whose plan hashes to the same value already holds exactly what this run would write, so the run skips it.
`--force` rewrites every board regardless; clearing a board drops its fingerprint, so the next seed rebuilds it.

**Every step prints where it has got to, on a two-second clock, with a rate and an ETA**, and the recipe prints a per-step table at the end.
Nothing waits without a deadline: every Firestore call has 30 seconds and six attempts, and every step has a wall clock, so a wedged step is killed and named rather than waited on.
If a run goes quiet, it is not working - that is a bug, and it will say so.

This was not always true.
`db.bulkWriter()` strands its last few writes under load - reproduced 6/6 against staging, where six processes each queued 20,000 writes, settled about 19,985 of them, and left every `close()` promise pending 90 seconds later at 0% CPU with no open connection.
A seed awaiting that promise waited forever, printed nothing, and could not be told apart from a dead process without sampling it in a debugger.
`scripts/lib/firestore-bulk.mjs` replaced it with `db.batch()` commits through a worker pool, which is both bounded and about four times faster.

## What "content-ready" means

A screenshot of an empty app sells nothing, and "looks good" is not a state anyone can reproduce.
So the definition is a set of numbers in `scripts/seed/lib/content-ready-contract.mjs`, asserted after every seed and re-checkable at any time:

```bash
node scripts/seed-content-ready.mjs verify --email you@example.com
```

`verify` only reads, and it runs the filmable check below as well, so one command answers both "does staging hold the content" and "would the app show it".
Run it after a capture session, after a real climb, or a week later, to find out whether staging is still worth pointing a camera at.

| The account has | Why |
|---|---|
| 7 landmark climbs finished | Fills the Collection grid and gives the globe somewhere to have been |
| 12 sessions across 42 days | Best Efforts ranks a history; a record book with six rows in it reads as a first week |
| A First Ascent it genuinely holds | The retention hook, on screen. First ever, not only ever: the check is that the account finished that board first (`globalCompletionOrder == 1`), which is what the app itself counts - climbers finishing it afterwards is the board working |
| Newest session today, oldest 42 days back | Relative dates are what give a stale account away |
| Standing rows in all five leaderboard windows | A rank exists to point a camera at |

| The world has | Why |
|---|---|
| 26 contested climb boards, 14 of them with 20+ finishers | A rank nobody had to earn is not worth capturing |
| 31 climbs with an open First Ascent | The claimable state has to be showable, and claimable for real on camera |
| 894 seeded rows, every one with a face and a full human name | A leaderboard of lettered circles is not what anyone is photographing |
| 2 routine templates and 12 profile personas with avatars | The routines, profile and global leaderboard surfaces are not empty |

The numbers are the contract.
Changing one is a deliberate change to what the captured content shows, not a tuning detail.

## Is it filmable? The check that reads what the app reads

Everything above answers a question about Firestore.
The seed's own summary, the fixture audit and the content-ready contract all confirm that documents were written, and none of them confirms that a climber opening the app sees a populated product.

That gap cost two and a half days.
Staging was reported ready and was not: leaderboards that rendered empty, four rivals instead of a field, and the entire bottom half of the Empire State Building with nobody in it while its own summary said 85 climbers had finished it.
The summary was not wrong about what it held.
It was answering a different question than the screen.

```bash
node scripts/verify-filmable.mjs --project staging --email you@example.com
```

It reads every surface the way the app reads it - the same collections, the same aggregates, the same query shapes - and prints one named line per surface with the measured number and the expectation beside it.
It takes about two seconds, so it is meant to be run after every seed, and `seed-content-ready.mjs` runs it as its last step and refuses to report success when it fails.

Three rules make it worth trusting:

- **Where the app runs a Firestore `count()` aggregate, the check runs the same aggregate over the same path.**
  Climb detail's "N completed" is `count(live_replay_leaderboards/{key}/splitBuckets/0/entries)` at runtime, and the board summary's `completedCount` is fetched, held for a few milliseconds and then overwritten by it.
  Reading the stored field instead of the aggregate is precisely the discrepancy that made a board with four rows look like a board with eighty-five.
- **A read that failed is never rendered as a read that came back empty.**
  A broken query and an empty collection both print nothing, and a check that conflates them is how a production leaderboard holding thirteen entries was once reported as holding none.
  A failed read is `ERROR`, it exits 2, and it says that nothing about that surface is known.
- **A live race's field may only ever thin.**
  A climber leaves a race by finishing it; nobody joins one part way up a building.
  So the entry counts across ascending split buckets have to be non-increasing, and any rise is rows missing from every bucket below it.
  A field falling from 85 to 81 partway up is four climbers finishing and is correct; a field of 4 at the base and 81 near the summit is the Empire State defect, and the check names the bucket, the elapsed time, and how many rows are missing.

`scripts/lib/app-render-contract.mjs` holds the client parsers, mirrored field for field, so a row Firestore holds but the app drops - an `identityPolicyVersion` from a previous policy, an achievement type this build cannot name, a routine template published for a later version - is counted as what it renders as, which is nothing.
`scripts/lib/filmable-report.mjs` holds the judgment, and both are pinned by tests that run without a network.

## First Ascents: what seeding spends, and what it leaves

A First Ascent is permanent.
The server lets a finisher claim one only when the board has **no completions and no holder** (`publishLiveClimbCompletion` in `functions/src/liveReplayLeaderboard.ts`), which is what makes it worth holding.

That rule has a consequence for seeding: **every climb the seed fills with synthetic competitors spends its First Ascent for good.**
That is the rule working.
What was wrong is that staging offered four claimable climbs out of thirty-two, because the remaining raceable climbs had no leaderboard summary at all - and the open-slot surfaces key off an existing summary (`ProfileFirstAscentService` requires `updatedAt != nil && completedCount == 0`), so a climb with no document reads as nothing rather than as an opportunity.

The split is now explicit and lives in `scripts/seed/lib/live-replay-climb-tiers.mjs`:

- `ACTIVE_CLIMBS` and `WARM_CLIMBS` - 26 boards seeded with finishers, so leaderboards are contested. Their First Ascents are spent.
- Every other raceable climb - seeded with an empty summary, so its slot is open *and* visibly open.

The account's own First Ascent therefore has to sit outside the contested set, or it renders as first-ever beside climbers who finished before it.
`seed-demo-user.mjs` refuses a contested climb rather than writing that contradiction, and the default is 875 North Michigan Avenue - the John Hancock Center, home of the Hustle Up the Hancock.

Which four climbs reach the profile's open preview is unchanged: it fills in catalog order and caps at four, and those four sort ahead of the newly opened ones.

## Every row on screen has to read as a person

A leaderboard is the product's shop window, so what a row carries is content, not fixture detail. Two supplies have to line up, and neither shortfall is visible in the seed's own output - only on a screenshot.

**Faces.** The 83 avatar images live in Firebase Storage under `live-replay-avatars/<seedPackId>/`. Uploading them needs a local image folder, which nobody has months later, so a run without `--avatar-dir` used to publish no photo at all. It now reads the existing objects back instead and rebuilds their download URLs from the tokens stored on each object, so no folder is needed and a climber's face stays the same across re-seeds. Pass `--avatar-dir <path>` only to replace the set.

**Names.** `SEEDED_DISPLAY_NAMES` is 82 long, one per competitor avatar, and no board seeds more finishers than that. Both limits are enforced by `assertSeededIdentitySupply`, which fails the run rather than let a config quietly reintroduce `Climber 061` - the placeholder five boards were already using, Empire State Building among them.

They are full names, and that is not cosmetic. `SuppliedNameAdoption` publishes whatever Sign in with Apple or Google hands over, which is a given name and a family name, so every real leaderboard row carries a full name. An abbreviated fixture reads as a fixture beside one, which is what a podium showed when the seed's `Tyler R.` stood next to the capture account's own `Tyler Pavay`. `unphotographableDisplayName` now rejects an initial for a surname, so the pattern cannot come back.

**Everybody else on the board.** The seed dresses its own climbers and the recipe dresses the capture account; nobody owned the rest. QA and tester accounts that signed into staging, finished a climb and left a finisher document behind carried whatever name their sign-in produced - `CHANGE ME` (the placeholder `SignInNamePlaceholder` publishes for an Apple account that supplied no name), `Content Capture`, `Climber 6J84R7` - onto the same podiums a camera points at.

The recipe now repairs them, after both seeds so it can see the names they publish and avoid colliding. It writes `users/{uid}/public_profile/current` and nothing else: that is the one validated write path for account-authored identity, and the deployed `onPublicProfileIdentityWritten` trigger carries the new name to `leaderboard_stats` and every replay projection. Names are assigned by uid, so a re-run does not shuffle who is who between capture sessions.

Two things it will not do. It never renames an identity a fixture owns - a persona publishing an unfit name is a defect in `profile-fixtures.mjs`, and a rename here would last exactly until the next seed, so those fail the run instead. And it never invents a photo: a face has to be a picture somebody chose, the avatar pool has exactly one image per synthetic climber plus one reserved for the capture account, and there are none spare. Accounts with no photo are listed with the command that gives them one:

```bash
node scripts/dev-db.mjs hydrate-user --project staging --user <uid> --photo-url <storage download url>
```

**The account's own name.** Whatever it publishes is what a screenshot shows, so the seed no longer derives one from an email local part: an address is an identifier, not a name. It uses `--display-name`, else the account's own Auth name, else a plain human fallback, and says which it chose. Synthetic rows are told apart by `isSynthetic`, `source` and `seedPackId`, so nothing needs the display name to carry a marker.

`verify` reads all of this back off the stored rows and fails on any seeded row with no photo or a machine-shaped name, and on an account publishing a placeholder.

## Getting back

```bash
node scripts/seed-content-ready.mjs clear --email you@example.com --dry-run
node scripts/seed-content-ready.mjs clear --email you@example.com
```

`clear` reverses the recipe in the opposite order - the account's seeded documents first, then the world fixtures.
The order matters: clearing the world first would zero a board's completion count while the account's rows were still standing on it.

**What it hands back.**
Every seeded board is zeroed and its First Ascent fields deleted, so all 59 climb boards read as claimable again, including the ones the pack had contested.
That is the state to clear into when what you want to film is claiming a First Ascent.

**What it cannot undo.**

- **Climbs performed in the app.** Delete those in the app. The device holds its own SwiftData copy, and only the app's own delete removes both it and the cloud document; a server-side delete would strand the local one.
- **The account's identity.** Display name, photo, age, weight and location belong to the person signed in, not to the fixture, so `clear` leaves them alone.
- **A First Ascent the account holds on a board other climbers have also finished.** Removing the holder would leave completions with no holder, which is a state the app can never produce or leave. `seed-demo-user.mjs clear` refuses rather than writing it, and says to re-seed that climb's pack instead. The recipe cannot produce that shape - it is a guard against a hand-run seed that did.
- **Anything in production.** Nothing here can reach it.

## The seeded climbs are published by the server, not just written

Writing `users/{uid}/workouts/{workoutId}` fires `onWorkoutReplaySplitsWritten`, so the account's seeded climbs go through the same publish path a real climb does.
The server writes its own finisher rows, replay entries and immutable rank-at-completion snapshots, and claims the First Ascent on the open board the account finishes.
This is why the seeded content behaves like earned content rather than looking like it: the numbers on screen were derived by the code that derives them in production.

It also means the seed cannot get ahead of the server.
`clear` deletes the workouts, and the trigger reconciles what it owns from that - which is why the clear leaves `live_climb_community_stats` alone rather than subtracting from a counter the server is already subtracting from.

## On the capture device

The app is local-first.
Seeding changes the cloud; the phone keeps whatever it already had until it hydrates.

`WorkoutHydrationService` runs once per app launch per signed-in account and applies a remote document whose `updatedAt` is newer than the local copy, so after a re-seed:

- **Relaunch the app** to pick up the refreshed sessions.
- **Reinstall, or sign out and back in**, for the cleanest result - a fresh local store takes exactly what staging holds.
- Sessions the seed does not know about stay on the device. Hydration only adds and updates; it never deletes.

Staging requires a server-owned `app_access` grant for paid data, so the capture account needs a reconciled sandbox purchase before any of this renders (`docs/revenuecat-server-entitlement-enforcement.md`).

## What runs, in what order

`seed-content-ready.mjs` owns the recipe and composes the existing scripts; it reimplements none of them.

1. `dev-db.mjs seed --target profiles,leaderboard,live-replay,routine-templates` - competitors, global standings, replay boards, routines.
2. `seed-demo-user.mjs seed --user <uid>` - the named account's climbs, records, standings and First Ascent.
3. The board-identity repair above - every other account's published name.
4. `audit-seed-data.mjs --target all` - the existing fixture audit.
5. The content-ready contract above.
6. `verify-filmable.mjs --user <uid>` - the filmable check above, which is what stops the recipe stamping "done" on a board the app renders as empty.

Two edges in that order are load-bearing:

- `leaderboard` reads the public identities `profiles` publishes, so it cannot run first against an empty environment.
- `live-replay` writes a synthetic First Ascent holder and a completion count onto the same summaries the account seed merges into, so the account must run **after** it. Reversed, the synthetic holder overwrites the account's claim.

`node scripts/seed-content-ready.mjs plan` prints this without touching an environment.

## Related

- `ascend-dev-fixtures` - the seeding policy the individual scripts follow.
- `docs/app-store-screenshots-brief.md` - what a shipped screenshot set has to hold to.
- `AppStoreAssets/README.md` - the renderer that turns captures into the upload set.
- `ascend-data-investigation` - how to check what staging actually holds before believing a zero.
