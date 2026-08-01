# Remote kill switches and phased release

An iOS binary cannot be rolled back.
Once a build is on a device, the only ways to change its behaviour are a new App Store submission - days at best - or changing something the running app reads from a server.
This document covers the second one.

## The switches

Every automatic, bulk path that decides the *shape* of persisted data sits behind a Firebase Remote Config boolean.
The catalog is `AscendApp/Shared/Services/RemoteConfig/RemoteFeatureFlag.swift`; the checked-in template is `remoteconfig.template.json`.

| Parameter | Turning it off stops | Deferred work |
|---|---|---|
| `workout_cloud_backup_writes_enabled` | Uploading workout documents and heart-rate sidecars | Workouts stay `pendingUpsert` in SwiftData and flush on the next pass |
| `workout_remote_deletes_enabled` | Deleting remote workout documents and sidecars | `PendingWorkoutDeletion` rows stay queued and replay |
| `workout_cloud_restore_enabled` | Decoding cloud backups into local storage | The next bootstrap still treats it as the initial hydration |
| `workout_media_uploads_enabled` | The background media upload queue, and the sweep that deletes local originals. A batch already running stops at the next item rather than finishing | `PendingMediaUpload` rows stay queued and local files stay on disk. The workout banner stays quiet rather than claiming an upload is in progress, and drops the retry affordance |
| `local_data_migrations_enabled` | One-shot local backfills that rewrite stored workouts | The version key is not stamped, so the backfill runs later |
| `leaderboard_publishing_enabled` | Publishing leaderboard stats, retiring legacy stat documents | Local stats stay dirty and republish. **Exception:** the legacy stat sweep is dropped, not deferred - see below |
| `public_profile_publishing_enabled` | Publishing the public profile mirror, stats, summaries | Republished from local state on the next bootstrap |

The invariant across all of them: **a blocked path defers its work, it never drops it.**
Pending state survives untouched, so turning a switch back on drains the queue with no user action and no further release.

One documented exception, and it is deliberate.
`LeaderboardService.deleteLegacyRemoteStats` runs only in the launch that rebuilds local stats onto the current schema, and that rebuild is one-shot: once the rebuilt stats are saved, `needsCurrentSchemaRebuild` never returns true again.
A device whose one rebuild happened while `leaderboard_publishing_enabled` was off therefore never sweeps its legacy stat documents.
Those documents are already superseded by the current-schema ones, so the whole cost is a stale row that nothing reads - which is why this is left as a drop rather than given a queue of its own.
Do not read the invariant above as universal without this line.
`AscendAppTests/RemoteFeatureGateTests.swift` pins it for the five gates whose collaborators can be faked - backup writes, remote deletes, cloud restore, media uploads, and local backfills - including the "turn it back on and the queue drains" half.
The remaining two (leaderboard publishing, public profile publishing) reach shared services that would need a live backend to observe, so their gates are reviewed rather than tested; making those injectable is worth doing the next time either is touched.

### What is deliberately not gated

The line is **automatic and bulk** versus **user-initiated and singular**, not "writes to Firestore".

Gated: the queues, sweeps, restores, and backfills that run on their own, touch many records, and finish before anyone notices they were wrong.
That is where a shipped bug does damage at scale.

Not gated: writes a person made happen and is watching - saving a profile edit (`UserDataRepository`), blocking or reporting a climber (`ModerationRepository`), submitting feedback (`FeedbackService`), registering a push token.
Each is one record, visible, and immediately correctable.
A kill switch there would not protect data; it would break the app while looking like a bug, and an unusable app is not a safer one.

If a bug reaches those paths, the lever is a fixed build - which is exactly why the automatic paths, which cannot wait that long, are the ones with switches.

## Flipping one

1. Firebase console -> Remote Config -> the project (`ascend-prod-9c8f2` for production).
2. Set the parameter to `false` and publish.
3. Running apps pick it up within seconds through the real-time listener; suspended apps pick it up on their next foreground.

There is nothing to build, submit, or wait for review on.

To confirm it landed on a specific build, open **Remote Flags**, which shows each flag's resolved value and whether it came from the server or from the shipped default.
On dev builds it sits inside Settings -> Developer -> Debug Tools; on staging builds, where the rest of Debug Tools is compiled out, it is its own Settings -> Developer row.
Release builds ship neither.

## What happens when the fetch fails

**Chosen posture: fail to the last known good value, and failing that, to the compiled-in default - which is `true` (feature enabled) for every current flag.**
A fetch failure never changes app behaviour on its own.

Resolution order, per flag:

1. The value the backend most recently supplied for this device.
   The Firebase SDK persists activated values across launches, and `RemoteFeatureFlagService.configure()` reads them into the store synchronously at launch, before the first fetch is even attempted.
   That read cannot fail, so this step survives a cold start with no network - it does not wait on, or depend on, a fetch succeeding.
2. The flag's `shippedDefault` in `RemoteFeatureFlag.swift`.

Only values the SDK reports as `.remote` count for step 1, so an unfetched or unparseable key still falls through to step 2.

Why fail *open* rather than closed:

- **A fetch failure means "offline", not "kill it".**
  Overwhelmingly, a failed fetch is an aeroplane, a tunnel, or a captive portal.
  Treating that as "off" would mean an ordinary offline launch silently stops backing up workouts - the safety mechanism would become the leading cause of the data loss it exists to prevent.
- **The blast radius does not widen.**
  Every gated path writes to Firestore or Cloud Storage.
  A device that cannot reach Remote Config almost certainly cannot reach those either, so failing open rarely permits a write that would otherwise have been blocked.
- **The switch is durable once seen.**
  A device that has fetched `false` keeps it across cold launches without a network.
  Only a device that has *never* successfully fetched runs on the shipped default, and that device is, by definition, one the backend has never been able to talk to.

Two supporting decisions:

- **No `setDefaults` on the SDK.**
  Defaults live in `RemoteFeatureFlag.shippedDefault` and nowhere else.
  Handing them to the SDK too would make `RemoteConfigValue.source` report `.default` for an unfetched key, destroying the distinction between "the server said on" and "nobody has ever answered".
- **Strict boolean parsing.**
  A parameter whose value is not a recognisable boolean is treated as absent, not as `false`, and logs `remote_config_value_unparseable`.
  A malformed template entry must not disable a data path nobody chose to disable.
  Declare these as **Boolean** parameters in the console and the question never arises.

Tests: `AscendAppTests/RemoteFeatureFlagResolutionTests.swift`.

## Deploying the template

The template is checked in so the parameters exist, identically, in all three projects.
Publishing it is a **full replace**, so a naive deploy would republish every switch as `true` and silently undo an active kill switch.

Consequences, both deliberate:

- Remote Config is **not** in the CI deploy `--only` lists. `scripts/test/remote-config-template.test.mjs` fails if it ever is.
- `scripts/deploy-remote-config.mjs` reads the live template first and refuses when any managed flag is currently off, unless you name each one you mean to re-enable.

```bash
cd scripts
npm run remoteconfig:deploy            # dev, dry run
npm run remoteconfig:deploy -- --apply
npm run remoteconfig:deploy:staging -- --apply
npm run remoteconfig:deploy:production -- --apply
```

To restore normal behaviour, flip the parameter back to `true` in the console.
Deleting the parameter also works - the flag falls back to its shipped default, which is `true`.

## Cost

Remote Config moves to usage-based pricing on **1 September 2026**.
Verified against <https://firebase.google.com/docs/remote-config/pricing> on 31 July 2026:

- Spark: 100,000 fetch requests per day at no cost.
  Over that, after a one-time 30-day grace period, requests past the threshold are throttled server-side.
- Blaze: first 100,000 daily fetches free; 100,001-10,000,000 at $0.000006 per request ($0.06 / 10K); above 10,000,000 at $0.000001 per request ($0.01 / 10K).
- A fetch request is any client or server call to the Remote Config backend for updated values.
- **Holding a real-time connection open is not itself billed.** Only the download that follows a server-pushed invalidation counts as a fetch.

Ascend's usage shape, given that:

- One fetch at launch, one per foreground, throttled by `minimumFetchInterval` - 1 hour in Release, 0 in Debug and Staging so QA sees a flip immediately.
  A cached answer inside the window costs nothing.
- Real-time updates carry the urgency, so the periodic fetch is only a backstop for a dropped connection.
  Ascend does not poll.
- At roughly two to three billable fetches per active user per day, the 100,000/day free tier covers on the order of 30,000-50,000 daily active users before a cent is charged.
  This is not a cost concern at Ascend's scale, and the design does not need to be built around it.

## Phased release

Phased release rolls an update out over seven days to users with automatic updates on: **1%, 2%, 5%, 10%, 20%, 50%, 100%**.
Verified against <https://www.developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases> on 31 July 2026.

**It does not apply to an app's first release.**
Version 1.0 goes to 100% of whoever downloads it, immediately.
Phased release starts mattering at 1.0.1.
On launch day, the kill switches above *are* the rollback.

Arm it on a version before it is submitted:

```bash
cd scripts
npm run phased-release:status
node appstore-phased-release.mjs enable --confirm
```

### Halting a rollout mid-flight

```bash
cd scripts
npm run phased-release:pause          # freezes the rollout where it is
```

`pause`, `resume`, and `release-to-all` resolve to the one version whose phased release is `ACTIVE` or `PAUSED`.
If none is, or more than one is, the command refuses and prints what it found rather than acting on a superseded version and reporting success.
`status` reports on that same version, falling back to the newest when nothing is rolling out, and names any newer record it skipped - so a version sitting in `PREPARE_FOR_SUBMISSION` is never mistaken for the rollout in flight.
Add `--version <versionString>` to name the target explicitly.
`scripts/test/phased-release-selection.test.mjs` pins that selection.

Or: App Store Connect -> the version (status **Ready for Distribution**) -> Phased Release -> **Pause Phased Release**.
Requires Account Holder, Admin, or App Manager.

Pausing stops *further* users being moved onto the build.
It does not remove it from anyone who already updated - which is exactly why a data-corrupting bug needs the Remote Config switch as well as, not instead of, a pause.

- Pausing is allowed for up to 30 cumulative days, with no limit on how many times.
- `node appstore-phased-release.mjs resume --confirm` continues from where it stopped.
- `node appstore-phased-release.mjs release-to-all --confirm` skips the remaining schedule and ships to everyone.
- If the app is removed from sale or the Developer Program membership lapses, the phased release stops permanently and the update goes to everyone on reinstatement.
  Paused progress is lost.

### Order of operations for a bad build

1. **Flip the Remote Config switch** for the affected path.
   This reaches every install, including the ones already updated, within seconds.
2. **Pause the phased release.**
   This stops the population of affected installs growing.
3. Fix, submit, and re-arm phased release on the new version.
4. Turn the switch back on once the fixed build has rolled out.
   Deferred work drains on its own.

Step 1 first, deliberately: the pause protects users who have not updated yet, the switch protects the ones who have.
