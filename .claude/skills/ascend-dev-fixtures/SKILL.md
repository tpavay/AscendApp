---
name: ascend-dev-fixtures
description: Use when seeding or clearing Ascend dev/staging data - the dev-db script, profile and leaderboard fixtures, live replay seed packs, debug workout seeding presets, the Firestore emulator, or Internal QA sign-in and its credentials. Covers the production refusal guard, why multi-user seeds must be server-side, and synthetic-data labeling.
paths:
  - scripts/**
  - AscendApp/Features/Debug/**
---

# Dev Fixtures, Seeding + QA

## Internal QA Sign-In
- Internal QA sign-in exists only for **dev** and **staging** builds and must stay unavailable in production.
- Internal QA sign-in must create a real Firebase-authenticated user session (email/password in dev/staging), not a fake authenticated client state.
- Gate the feature by both build configuration and Firebase project ID so the UI only appears for `ascend-f2e4f` and `ascend-staging-fa7d5`.
- Local simulator/automation credentials should come from user-local scheme environment variables or other non-committed secrets sources such as `ASC_INTERNAL_QA_EMAIL` and `ASC_INTERNAL_QA_PASSWORD`.
- XcodeBuildMCP simulator automation should inject `ASC_INTERNAL_QA_EMAIL` and `ASC_INTERNAL_QA_PASSWORD` through `session_set_defaults(env: ...)` or `launch_app_sim(env: ...)` instead of relying on user-local Xcode scheme environment inheritance.
- Do not persist Internal QA credentials in repo-local `.xcodebuildmcp/config.yaml`; keep them in user-local scheme settings or pass them into the MCP session at runtime.
- Never commit QA credentials, never bundle them into production builds, and never use the internal QA path to bypass Firestore/Storage/Auth server enforcement.
- A QA account is signed in, not paid. Staging rules require a server-owned `app_access` grant for paid data, so a QA session that has never completed a reconciled sandbox purchase gets `PERMISSION_DENIED` on workouts, routines, leaderboards, and workout media - that is enforcement working, not a broken fixture. `docs/revenuecat-server-entitlement-enforcement.md` owns the grant path; Admin SDK seeding is unaffected because it bypasses rules.

## Leaderboard Seeding Policy (Debug / CI)
- Firestore rules deny every client write to `leaderboard_stats`; standings are derived server-side from the canonical workouts (`functions/src/leaderboardStats.ts`). A seed that writes a standing must use the Admin SDK, and it must then choose one of two shapes, because the derivation owns every row it is not told to leave alone:
  - No workouts behind the standing (the `scripts/seed/fixtures/profile-fixtures.mjs` personas): mark the row `isSynthetic: true`, or the derivation deletes it the moment anything touches that persona's user document.
  - Real seeded workouts behind the standing (`scripts/seed-demo-user.mjs`): leave the row unmarked and derive its totals the same way the server does, so the rebuild lands on the same numbers. Never floor, pad, or round a seeded total the workouts do not support.
- Multi-user seed data should not be written from client debug tools in shared environments.
- Use server-side seeding (Admin SDK / Cloud Function / CI job) for deterministic multi-user leaderboard fixtures.
- For local-only iteration, use the Firestore emulator or seed only the authenticated user.
- Use `scripts/dev-db.mjs` as the central dev/staging database tool for repeatable fixture workflows. It can seed, clear, or reset `profiles`, `leaderboard`, `live-replay`, or `all`, and it must keep refusing production (`ascend-prod-9c8f2`) and unknown Firebase projects.
- Dev database cleanup should be target-scoped and metadata-driven. Do not hide an unrestricted project wipe behind a friendly `clear all` command.
  Full dev and staging wipes are separate commands carrying environment-specific confirmations - `npm run db:wipe` passes `--confirm-dev-wipe`, `npm run db:wipe:staging` passes `--confirm-staging-wipe` - and neither confirmation authorizes the other project.
  `scripts/lib/firestore-wipe-policy.mjs` owns the decision: the deletable set is every direct top-level match in `firestore.rules` plus its short named list of retired collections whose producers are gone, `_migrations` is recognized and preserved so migration audit history and rerun protection survive a reset, and any live collection in neither set fails the wipe closed before anything is deleted.
  A new top-level collection therefore keeps resets working by being declared in the rules, which is the obligation `ascend-firebase-data` states for rules authors.
- Profile fixture data must include the full public profile contract: display name, age, gender, `weight_kg`, `location_country`, optional `location_region`, `joined_at`, public profile mirror, profile stats, achievements, and public workout summaries.
  Seeded public profile mirrors and leaderboard rows may retain authored fixture identity when they carry the trusted synthetic marker expected by their schema.
  Real-user fixture projections follow the same validated account identity and shared moderation boundary as production data (see `ascend-profile`).
- Every seeded public profile mirror and leaderboard row must carry the identity contract fields its schema requires.
  `users/{uid}/public_profile/current` needs `identityPolicyVersion` and `identityChangedAt`; `leaderboard_stats` rows additionally need `identityState`.
  Strict `hasOnly`/`hasAll` means a seeder that omits them is denied outright, so keep `scripts/seed/fixtures/profile-fixtures.mjs` as the reference shape.
- Fixture display names must satisfy the same screening as production names - `DisplayNamePolicy` in Swift, `isAllowedDisplayName` in `functions/src/publicIdentity.ts`, and `isAllowedDisplayName` in `firestore.rules` all agree, and a name any one of them rejects is rejected for a fixture too.
- `scripts/seed/lib/public-identity-contract.mjs` is the JavaScript home of that contract - the display-name screening, the photo-URL pattern, and `assertPublishablePublicIdentity`.
  Every seeding entry point validates through it, because the Admin SDK bypasses `firestore.rules` and is therefore the one writer that could publish an identity the server would strip on projection.
  `SharedTestVectors/display-name-screening-vector.json` pins it against the Cloud Functions implementation; add a case there rather than editing one screening copy in isolation.
- `hydrate-user` also refuses to *invent* a public display name: with none passed and none stored it errors rather than publishing a placeholder.
  `create-auth-user --hydrate-profile` pre-flights the same requirement before it calls `auth.createUser`, so a missing `--display-name` fails the command instead of leaving an orphaned Auth account with no Firestore user document.
  The app's own fallback for a nameless account is `PublicClimberIdentity.systemHandle`, a per-uid handle ("Climber A3F9MQ"). A bare "Climber" collides across every account that took the fallback and is indistinguishable from a real name once it reaches a podium - staging carried exactly that on its top weekly and yearly row, written by a build that predates #263.
- `scripts/dev-db.mjs hydrate-user` fails before writing when `--display-name` fails screening or `--photo-url` is not a Firebase Storage download URL, including when the offending value is inherited from the existing user document rather than passed on the command line.
  To publish no photo, pass `--photo-url ""` or `--clear-photo`; either one wins over a stored `profilePictureURL` instead of falling back to it.
  That is the escape for stale seed data whose `profilePictureURL` predates the identity contract, and for `create-auth-user --use-existing-auth-user --hydrate-profile` when the Auth record carries a provider photo the contract does not accept.
- Fixture `photoURL` values must be Firebase Storage download URLs (`https://firebasestorage.googleapis.com[:443]/v0/b/<bucket>/o/<object>`).
  Rules reject any other host, and the identity propagation trigger drops one rather than copying it onto a projection, so a fixture pointing at an external avatar service loses its photo on the way to the leaderboard.
  The `:443` is not optional cosmetics: the Firebase iOS SDK builds download URLs through `URLComponents` with `port` set to `Storage.port`, which defaults to 443, so every real upload carries it. Validate any new photo-URL rule against a captured SDK string, never a hand-written one.
- Profile persona avatars are twelve curated 512x512 JPEGs committed at `scripts/seed/assets/profile-avatars/<personaId>.jpg`, one distinct image per persona.
  They live in the repo rather than behind an `--avatar-dir` flag so the seed reproduces for anyone without a local image folder.
  `scripts/seed-test-users.mjs` uploads them to `users/{uid}/profile_pictures/<seedPackId>.jpg` - the owner-scoped prefix `storage.rules` already governs, never a shared root path - mints a download token per object, and injects the resulting URLs into `buildProfileSeedWrites`.
  The object name is deterministic, so re-seeding overwrites in place instead of orphaning objects.
  A persona with no uploaded avatar publishes no photo; an off-host URL fails the seed rather than reaching Firestore.
- Dev and staging seed data written before the account-authored identity change is stale: its mirrors predate the identity contract and its leaderboard rows predate `identityState`.
  Repair them with `scripts/restore-public-identities.mjs --env <dev|staging> --apply`, which stamps the missing
  `identityPolicyVersion` and `identityChangedAt` onto `users/{uid}/public_profile/current` and lets the deployed
  `onPublicProfileIdentityWritten` trigger fan the identity out to every projection.
  Dry run is the default: without `--apply` it prints the per-user plan and writes nothing.
  Prefer it over re-seeding: it preserves the numbers already being tested against, and it screens every derived name
  through the same shared contract the live write path uses, skipping any account whose identity it cannot derive
  rather than inventing one.
  It writes only the public profile mirror - never `leaderboard_stats` - and hard-refuses production, which holds
  nothing to repair.
  `--verify` reads the leaderboard rows back and reports which ones the client would still drop.
  A row whose owner has no `public_profile/current` is unrepairable by any tool: only the account itself can publish
  one.
  The fan-out depends on the propagation functions being deployed to the target project; dev's functions deploy
  currently lacks them, so a dev backfill repairs the source mirrors and waits.
- To create one dev/staging QA Auth account, use `scripts/dev-db.mjs create-auth-user`. It must stay dev/staging-only, can generate a password, and can optionally run `--hydrate-profile` or `--seed-demo-data` after the Auth account exists.
- To patch one dev/staging account, use `scripts/dev-db.mjs hydrate-user` so private `users/{uid}` and public `users/{uid}/public_profile/current` stay in sync.
- `scripts/seed-demo-user.mjs` derives every demo user's leaderboard totals from the workouts it seeds, mirroring `aggregateForPeriod` in `functions/src/leaderboardStats.ts`, and writes no row for a period with no workouts in it.
  The rows are deliberately not marked `isSynthetic`: a demo user has real workouts behind the standing, so the server derivation owns the row and rebuilds it to the same numbers.
  It used to floor totals at a `minimumStepsByTimeFrame` (640,000 yearly, and so on), which is where identical demo totals and the podium ties they produced came from.
  That floor is gone, so demo standings now differ per account and match the seeded workouts.

## Live replay seeding
- Live replay leaderboard seed data must be Admin SDK/server-written into the read-only `live_replay_leaderboards` index, never client-written during a live session.
- `scripts/seed-live-replay-leaderboards.mjs` may write only to dev (`ascend-f2e4f`) or staging (`ascend-staging-fa7d5`) and must hard-refuse production or any unknown project; use environment-specific seed packs for repeatable active/warm Live Climb replay fixtures.
- Live replay seed entries must carry `isSynthetic`, `source`, and `seedPackId` so synthetic replay data can be filtered, cleared, or phased out later. Do not claim seeded replay rows are users climbing right now.
- Live replay seed data must not reuse the same synthetic profile name or photo within a climb. Duplicate profiles make the replay look like one person appears multiple times.
- Seeded replay summaries must stay on a First Ascent state the app can actually reach: completions imply a holder, and an open slot implies zero completions.
  Seeding completions without `firstAscent*` fields permanently kills the slot, because the server only claims it when there are no completions and no holder.
  `scripts/seed/lib/live-replay-first-ascent.mjs` owns this contract and fails the seed plan when it is violated; keep its field list in sync with `firstAscentWrite` in `functions/src/liveReplayLeaderboard.ts`.
- A seeded replay board must carry finisher documents beside its entry rows (`scripts/seed/lib/live-replay-finisher.mjs`), clearing a pack has to take them back out, and the seeded `completedCount` is derived from the finishers left standing afterwards.
  `ascend-live-climbs` owns why: the permanent rank a finished climb freezes counts finishers, so a board of entries with no finishers reads as an empty field.
- Seeded replay curves should be calibrated from historical workout pace distributions when available.

## Script Dependency Policy
- `scripts/` stays on `firebase-admin` 13.x. Do not bump to 14.x - 13.x is what preserves the declared Node 20 support (`engines.node: >=20`).
- `scripts/package.json` overrides `uuid` to `^11.1.1`. `google-gax`, `gaxios`, and `teeny-request` still request uuid 9, but the only surface those consumers exercise is the v4 API, which is unchanged across the major. Keep the override; dropping it reintroduces the vulnerable uuid 9 tree.

## Workout Seeding Policy (Debug)
- Debug Tools includes local SwiftData workout seeding presets for Simulator workflows (`App Store Screenshots`, `Quick Demo`).
- Seeded workout metadata is stored in `Workout.sourceMetadata` with `isTestData=true`, `seedSource="debug-tools"`, and `preset` for targeted cleanup.
- Workout seeding is idempotent for debug usage: seeding replaces existing debug-seeded workouts before inserting the new preset.
- Clearing seeded workouts must recalculate derived workout data and local leaderboard aggregates to keep derived data consistent.
- Weighted vest debug data should use an intended pounds range and convert to kilograms when measurement system is metric.
