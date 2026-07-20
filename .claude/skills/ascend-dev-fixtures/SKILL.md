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

## Leaderboard Seeding Policy (Debug / CI)
- Firestore client rules only allow writes to `leaderboard_stats` where `userId == request.auth.uid`.
- Multi-user seed data should not be written from client debug tools in shared environments.
- Use server-side seeding (Admin SDK / Cloud Function / CI job) for deterministic multi-user leaderboard fixtures.
- For local-only iteration, use the Firestore emulator or seed only the authenticated user.
- Use `scripts/dev-db.mjs` as the central dev/staging database tool for repeatable fixture workflows. It can seed, clear, or reset `profiles`, `leaderboard`, `live-replay`, or `all`, and it must keep refusing production (`ascend-prod-9c8f2`) and unknown Firebase projects.
- Dev database cleanup should be target-scoped and metadata-driven. Do not hide an unrestricted project wipe behind a friendly `clear all` command; full destructive wipes need an explicit, separately guarded command and a reviewed collection list.
- Profile fixture data must include the full public profile contract: display name, age, gender, `weight_kg`, `location_country`, optional `location_region`, `joined_at`, public profile mirror, profile stats, achievements, and public workout summaries.
- To create one dev/staging QA Auth account, use `scripts/dev-db.mjs create-auth-user`. It must stay dev/staging-only, can generate a password, and can optionally run `--hydrate-profile` or `--seed-demo-data` after the Auth account exists.
- To patch one dev/staging account, use `scripts/dev-db.mjs hydrate-user` so private `users/{uid}` and public `users/{uid}/public_profile/current` stay in sync.

## Live replay seeding
- Live replay leaderboard seed data must be Admin SDK/server-written into the read-only `live_replay_leaderboards` index, never client-written during a live session.
- `scripts/seed-live-replay-leaderboards.mjs` may write only to dev (`ascend-f2e4f`) or staging (`ascend-staging-fa7d5`) and must hard-refuse production or any unknown project; use environment-specific seed packs for repeatable active/warm Live Climb replay fixtures.
- Live replay seed entries must carry `isSynthetic`, `source`, and `seedPackId` so synthetic replay data can be filtered, cleared, or phased out later. Do not claim seeded replay rows are users climbing right now.
- Live replay seed data must not reuse the same synthetic profile name or photo within a climb. Duplicate profiles make the replay look like one person appears multiple times.
- Seeded replay curves should be calibrated from historical workout pace distributions when available. Apple Health-derived step counts should be conservatively reduced before shaping synthetic attempts because imported stair-stepper data can overestimate steps.

## Script Dependency Policy
- `scripts/` stays on `firebase-admin` 13.x. Do not bump to 14.x - 13.x is what preserves the declared Node 20 support (`engines.node: >=20`).
- `scripts/package.json` overrides `uuid` to `^11.1.1`. `google-gax`, `gaxios`, and `teeny-request` still request uuid 9, but the only surface those consumers exercise is the v4 API, which is unchanged across the major. Keep the override; dropping it reintroduces the vulnerable uuid 9 tree.

## Workout Seeding Policy (Debug)
- Debug Tools includes local SwiftData workout seeding presets for Simulator workflows (`App Store Screenshots`, `Quick Demo`).
- Seeded workout metadata is stored in `Workout.sourceMetadata` with `isTestData=true`, `seedSource="debug-tools"`, and `preset` for targeted cleanup.
- Workout seeding is idempotent for debug usage: seeding replaces existing debug-seeded workouts before inserting the new preset.
- Clearing seeded workouts must recalculate derived workout data and local leaderboard aggregates to keep derived data consistent.
- Weighted vest debug data should use an intended pounds range and convert to kilograms when measurement system is metric.
