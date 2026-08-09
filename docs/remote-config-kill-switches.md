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
| `workout_sync_recovery_reopen_enabled` | Re-opening one automatic sync attempt for a workout whose retry series has stopped, after a build change, an epoch bump, or a repaired sign-in | Nothing is dropped: the stopped state is untouched and manual retry stays unlimited. Turning it back on re-opens on the next pass |
| `workout_cloud_restore_enabled` | Decoding cloud backups into local storage | The next bootstrap still treats it as the initial hydration |
| `workout_media_uploads_enabled` | The background media upload queue, and the sweep that deletes local originals. A batch already running stops at the next item rather than finishing | `PendingMediaUpload` rows stay queued and local files stay on disk. The workout banner stays quiet rather than claiming an upload is in progress, and drops the retry affordance |
| `routine_cloud_backup_writes_enabled` | Uploading user-authored routines and routine folders | Routines and folders stay `pendingUpsert` in SwiftData and flush on the next pass |
| `routine_remote_deletes_enabled` | Deleting remote routine and routine folder documents | `PendingRoutineDeletion` rows stay queued and replay. The routine they point at is still held back from re-upload, so the switch cannot resurrect a deleted routine |
| `routine_cloud_restore_enabled` | Decoding routine backups into local storage | The next bootstrap still treats it as the initial hydration |
| `apple_health_enrichment_enabled` | The background Apple Health pass that writes heart rate and calories onto climbs Ascend recorded | The attempt ledger is left completely untouched, so every pending climb resumes its own retry series when the flag returns |
| `local_data_migrations_enabled` | One-shot local backfills that rewrite stored workouts, and the bootstrap sweep that claims ownerless user-authored routines and folders - the ones that predate the backup and the ones saved while nobody was signed in - for the signed-in climber, catalog templates excluded | The workout backfill's version key is not stamped, so it runs later. The routine sweep stamps nothing at all: it is not one-shot, so it simply runs again on the next authenticated bootstrap after the flag returns |
| `public_profile_publishing_enabled` | Publishing the public profile mirror, stats, summaries | Republished from local state on the next bootstrap |

The invariant across all of them: **a blocked path defers its work, it never drops it.**
Pending state survives untouched, so turning a switch back on drains the queue with no user action and no further release.

`AscendAppTests/RemoteFeatureGateTests.swift` pins it for the five gates whose collaborators can be faked - backup writes, remote deletes, cloud restore, media uploads, and local backfills - including the "turn it back on and the queue drains" half.
Public profile publishing reaches a shared service that would need a live backend to observe, so its gate is reviewed rather than tested; making it injectable is worth doing the next time it is touched.

`leaderboard_publishing_enabled` was retired with issue #307.
The client no longer publishes standings at all - the server derives them from the canonical workouts (`functions/src/leaderboardStats.ts`), so the only kill switch that reaches the leaderboard now is `workout_cloud_backup_writes_enabled`: hold the workout backup and no new standing is derived, because the evidence never lands.
That is the correct choke point, and it defers rather than drops.

### Settings, which are not switches

A kill switch is a Boolean that ships on and is flipped off to stop a path.
A **setting** carries a value an operator moves deliberately, so treating it as a switch would make the healthy state a lie.
The catalog is `AscendApp/Shared/Services/RemoteConfig/RemoteConfigSetting.swift`, read through `RemoteConfigSettingReading` rather than the Boolean flag pipeline - widening that pipeline to carry numbers would put every kill switch's resolution at risk for the sake of one setting.

| Parameter | Type | Baseline | What moving it does |
|---|---|---|---|
| `workout_sync_recovery_epoch` | NUMBER | `0`, only ever increased | Grants every workout whose automatic sync series has stopped exactly one more attempt, fleet-wide, with no binary. `firestore.rules` deploys independently of app releases, so after a rules fix this is the only lever that unsticks the workouts that fix repairs. Gated by `workout_sync_recovery_reopen_enabled` |

An unfetched setting resolves to its `shippedDefault` for the same reason a flag does - only `RemoteConfigValue.source == .remote` counts - and zero is that baseline deliberately, so a device's first successful fetch cannot read as a bump.
Everything else in this document applies to settings too: `workout_sync_recovery_epoch` is published the same way, and the archive preflight refuses a build whose setting is unreachable exactly as it does for a switch.
The one difference is the type contract - a setting is held to its own declared type and baseline, not to `BOOLEAN` / `true`.

A moved setting is protected from the full replace exactly as an off switch is: the guard compares the live parameter against the checked-in one, so a bumped epoch stops the publish rather than being restated as `0`.
The client compares the recovery basis for *difference*, not magnitude, so a reset to `0` does not strand the lever - it fires it, re-opening every stopped sync series across the fleet at a moment nobody chose. That is `RemoteConfigSetting.workoutSyncRecoveryEpoch`'s "re-open on the way back down for no stated reason", and it is what the refusal exists to prevent.

**The epoch's refusal is permanent, and getting past it takes a follow-up.**
A kill switch returns to `true` and a version threshold returns to `0.0.0` when an incident closes, so both come back to parity with the checked-in template on their own.
The epoch never does: it is only ever increased, and the checked-in `"0"` is its floor rather than a state anyone wants live.
So from the first bump onward, `deploy-remote-config.mjs` refuses on it forever, and the only way past is `--allow-overwriting-active-kill-switch workout_sync_recovery_epoch`.

That override is safe **only** with the step after it:

1. Note the live value first - the refusal prints it, and so does the acknowledgement on the way through.
2. Publish with the override.
3. **Immediately set `workout_sync_recovery_epoch` back to at least that value in the console.** Leaving the project at `0` leaves the next genuine bump indistinguishable from the reset for any client that has not fetched in between.

The script spells this out with the concrete number rather than relying on this page, because it is needed at exactly the moment nobody is reading documentation.

### The version policy parameters, which are captain-only

Two settings are deliberately **not** published by any automation, in any project.
Their catalog is `AscendApp/Shared/Services/RemoteConfig/RemoteAppVersionParameter.swift`, read through `AppVersionGateState` rather than either of the pipelines above.

| Parameter | Type | Baseline | What moving it does |
|---|---|---|---|
| `minimum_supported_app_version` | STRING | `0.0.0` | Every installed build below this version is locked behind a full-screen refusal with one App Store action. There is no Later and no escape |
| `recommended_app_version` | STRING | `0.0.0` | Every installed build below this version is prompted to update and may defer with Later |

Both are compared semantically against `CFBundleShortVersionString`, so `1.10.0` is newer than `1.9.0`, and both ship inert at `0.0.0`.
Each threshold is judged on its own: an absent or malformed recommendation cannot suppress an armed minimum, and an absent or malformed minimum cannot suppress the recommendation.
Anything unparseable - a missing value, an empty string, `1.0-beta`, a current version the app cannot read - fails open for that threshold alone.
The minimum is enforced as a route resolved above authentication rather than as a sheet, so nothing presented over the app - the paywall included - can cover it (`AscendApp/App/AppRootRoute.swift`); the recommendation stays a dismissible sheet.

**They are excluded from the additive publisher on purpose** (`CAPTAIN_ONLY_PARAMETERS` in `scripts/lib/remote-config-template.mjs`).
Merging to `develop` publishes new *kill switches* to dev and staging automatically; it publishes neither of these anywhere.
A captain publishes them to dev, staging and production by hand, through the full replace below, and the pull request report says so by name at review time.
The archive preflight still requires them: a build that reads them refuses to archive against any project where they are unreachable, exactly as for a switch.

**Arming the minimum, mid-incident.**
This is the highest-blast-radius lever in the app, because a wrong value locks out the installed base and App Review with no binary to roll back to.

1. **Never set the minimum above the highest version that has already passed review and shipped.**
   A climber cannot update to a build that does not exist on the App Store yet, and neither can a reviewer.
   Anything higher is a fleet-wide lockout with no exit.
2. **Scope it with a Firebase App version condition**, so the block reaches the builds the incident is actually about rather than everything below the number.
3. **Rehearse on Staging first** - the exact condition and the App Store link, on a real device, before touching production.
   The link is Ascend's production product `6757202987` in every environment, so a Staging rehearsal exercises the real destination.
4. Return the parameter to `0.0.0` when the incident closes.
   Flip it, do not delete it: a deleted parameter blocks the next archive, for the reason under "Flipping one".

**A floor is durable once seen, exactly like a switch.**
Each device enforces the last floor the backend actually gave it, seeded from the SDK's persisted activation at launch before any fetch is attempted - so a climber who would hit the lockout online hits it offline too, and losing the network is not a bypass.
Only a device the backend has never answered has no floor to enforce.
The consequence at step 4 is that returning the parameter to `0.0.0` releases a locked device only once that device reaches Remote Config again.

**Arm and disarm in the console, not through the full replace.**
The checked-in template is pinned to the inert `0.0.0`, so publishing it is the one thing that can silently end a lockout: the payload restates `0.0.0`, and a condition scoping the block disappears with it.
`deploy-remote-config.mjs` therefore refuses while either threshold is armed - live parameter not identical to the checked-in one, conditions included - and names it the same way it names a kill switch that is off.
The same guard covers every setting, so a bumped `workout_sync_recovery_epoch` stops the publish too.
Overriding that refusal takes `--allow-overwriting-active-kill-switch <key>`, spelled out per parameter.
Adding a new *switch* to a project mid-incident is what the additive publisher is for, and it never touches these two at all.

### What is deliberately not gated

The line is **automatic and bulk** versus **user-initiated and singular**, not "writes to Firestore".

Gated: the queues, sweeps, restores, and backfills that run on their own, touch many records, and finish before anyone notices they were wrong.
That is where a shipped bug does damage at scale.

Not gated: writes a person made happen and is watching - saving a profile edit (`UserDataRepository`), blocking or reporting a climber (`ModerationRepository`), submitting feedback (`FeedbackService`), registering a push token.
Each is one record, visible, and immediately correctable.
A kill switch there would not protect data; it would break the app while looking like a bug, and an unusable app is not a safer one.

If a bug reaches those paths, the lever is a fixed build - which is exactly why the automatic paths, which cannot wait that long, are the ones with switches.

Also not gated: anything a Cloud Function or an operator-run script writes, such as the server-side leaderboard derivation.
Remote Config resolution is client-side, so a flag could not reach that code even if one existed, and a Cloud Function can simply be redeployed - the premise the whole mechanism rests on, that a binary cannot be rolled back, does not hold there.

## Flipping one

1. Firebase console -> Remote Config -> the project (`ascend-prod-9c8f2` for production).
2. Set the parameter to `false` and publish.
3. Suspended apps pick it up on their next foreground, and that is the path known to work.
   A running app is *meant* to pick it up within seconds through the real-time listener, but that has never been observed - see "The switch exercise" below.
   Plan an incident around the foreground fetch until someone confirms the listener on a device.

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

There are two publish paths, and the difference between them is the whole safety argument.

### The full replace, by hand

`scripts/deploy-remote-config.mjs` publishes the checked-in template as it stands.
That is the right thing for a person who has read the diff, and it is what puts a project into the healthy state after any divergence.
It reads the live template first and **refuses** while any lever is in use, unless you name each one you mean to overwrite.
Two shapes count: a managed flag currently off, and a **setting** moved away from its healthy baseline.
A setting has no "off" value to recognise - it is in use at whatever value an operator moved it to - so it is caught by comparing the live parameter against the checked-in one in full, conditions included.
That covers every entry in `SETTING_PARAMETERS`, enumerated from the catalog rather than named one by one: an armed version threshold, and a bumped `workout_sync_recovery_epoch`, whose reset to `0` is not a no-op but a fleet-wide re-open of every stopped sync series.
The epoch is the one lever whose refusal is permanent once it fires, because it is only ever increased and so never returns to the checked-in floor - see "Settings, which are not switches" for the override and the console step that has to follow it.

```bash
cd scripts
npm run remoteconfig:deploy            # dev, dry run
npm run remoteconfig:deploy -- --apply
npm run remoteconfig:deploy:staging -- --apply
npm run remoteconfig:deploy:production -- --apply
```

**No CI workflow may run it, by any route.**
`scripts/test/remote-config-template.test.mjs` closes all three: a deploy whose `--only` list names `remoteconfig`; a deploy carrying no `--only` at all, since `firebase.json` wires the template in and an unscoped deploy publishes it; and the repository's own full-replace path, whether run as `deploy-remote-config.mjs` or through any npm alias that invokes it.
The alias names are read out of `scripts/package.json` and the workflow list is read out of `.github/workflows/`, so neither renaming an alias nor adding a workflow can slip a full replace past the test.

### The additive publish, automatic

`scripts/publish-new-kill-switches.mjs` publishes only parameters the target project has never held, and it is what `deploy-staging.yml` runs against dev and staging on every push to `develop`.
It exists because publishing was a separate manual act nobody remembers: #367 added three switches, the repository was correct, nothing was published, and the 2026-08-03 staging archive stopped on `routine_cloud_backup_writes_enabled is missing from the live template`.

It publishes the automatically published parameters only; the captain-only version thresholds are excluded from its plan entirely, so a merge to `develop` never puts them into any project.

It cannot re-enable a switch, in two independent layers:

1. **The payload is built from the live template, never from the checked-in one.** Existing parameters, conditions and parameter groups cross over verbatim, so there is no code path that writes a checked-in value over a live one. Only keys the project has never held are added, and nothing is ever deleted - a retired parameter no current flag reads stays where it is.
2. **It refuses to write anything at all while any managed switch is off.** Remote Config publishes are full replaces, so the payload necessarily restates every live parameter, and a flip landing between the read and the write would be undone by a payload that was correct when it was built. Rather than race that, an automated run stops and names the switch. A human still can publish, with the full picture.

It also proves the write afterwards.
The backend increments `version.versionNumber` on every publish, so a post-publish version that is not exactly one past the version the run read means something else published in between; the run fails, names the intervening version and who published it, and **restores nothing** - reconciling would be a second automated write into a situation nobody understands yet.

A live value that differs from the checked-in template is reported and left exactly as it is, whatever the reason.

```bash
cd scripts
npm run remoteconfig:publish-new                       # dev, rehearsal only
npm run remoteconfig:publish-new -- --apply
npm run remoteconfig:publish-new:staging -- --apply
npm run remoteconfig:publish-new:production -- --apply
```

Without `--apply` it runs the real `firebase deploy --only remoteconfig` with `--dry-run`, so a rehearsal exercises the same command and stops before the write rather than describing what it would have done.

**Production is deliberately not automated.**
No workflow may invoke this script against `ascend-prod-9c8f2`, and a test in `scripts/test/remote-config-publish.test.mjs` fails if one ever does.
The additive argument would make it safe; widening what automation touches in production is a separate decision, and the production archive preflight already refuses to build while a flag is unreachable, so a missed publish stops the release rather than shipping a decorative lever.
`docs/production-backend-rollout-runbook.md` owns the captain-only step.

### Drift

`.github/workflows/remote-config-drift.yml` compares dev, staging and production against `develop` every Monday, and on demand through **Run workflow** - which is the form that matters mid-incident, when the question is "what is actually live in all three right now".

It is strictly read-only, production included.
An unreachable switch fails it; a switch someone has turned off is reported and does not, because using the lever is the mechanism working.

```bash
cd scripts
npm run remoteconfig:drift
```

To restore normal behaviour after using a switch, flip the parameter back to `true` in the console.

**Flip it, do not delete it.**
Deleting the parameter restores the same behaviour - the flag falls back to its shipped default, which is `true` - but it also removes the lever, and the archive preflight below refuses to build staging or production while a flag the binary reads is missing from the backend.
An operator who deletes rather than flips will block the next release, with nothing in the build log pointing at the console as the cause.
The same applies to switching a parameter to "use in-app default": the key stays visible in the console while the backend stops supplying a value, which the preflight treats exactly like a deletion.

### Publishing is not optional, and CI now checks it

Between #298 and #318 the template existed, was correct, and had never been published to any project.
Every flag resolved to its `shippedDefault`, the app behaved completely normally, and nothing caught it - because the only parity check compared the checked-in template to `RemoteFeatureFlag.swift`, and both of those were right.
The comparison nobody made was against the live backend, which was empty in dev, staging and production.

`scripts/ci/assert-remote-config-published.mjs <dev|staging|prod>` closes that.
It reads the live template and fails the staging and production archives when a parameter the build reads is unreachable on the backend it will talk to.
"A parameter the build reads" is every catalog enum - `RemoteFeatureFlag.swift`, `RemoteConfigSetting.swift` and `RemoteAppVersionParameter.swift`, listed once in `APP_PARAMETER_SOURCE_PATHS`.
An operator setting that exists only in the checked-in template is worse than no lever, because it is believed in: `workout_sync_recovery_epoch` is what unsticks a fleet after a rules fix, and it is reached for mid-incident.

Unreachable is wider than absent.
The condition that matters is `RemoteConfigValue.source == .remote`, the single thing `FirebaseRemoteFeatureFlagSource.remoteSourcedValues()` requires before a value counts, so the preflight refuses all of these:

- The parameter is **missing** from the live template.
- The parameter is set to **use in-app default**, so the backend deliberately supplies no value. The key is right there in the console and the flag still resolves from `shippedDefault` - the most deceptive shape of the lot.
- The parameter carries **only conditional values** and no default, so any client matching no condition receives nothing.
- The parameter is not declared at **its own type** - `BOOLEAN` for a kill switch, and whatever `SETTING_PARAMETERS` declares for a setting (`workout_sync_recovery_epoch` is `NUMBER`). Note carefully what this one is and is not: the client reads `stringValue` and never inspects `valueType`, so a `STRING` parameter holding `"false"` *is* honoured as a live kill switch. Do not read a type warning during an incident as "the switch is inert" - it may well be doing exactly what you asked. The declaration is refused because the template requires that type and because the console type is what stops a value the client's strict parser would drop from ever being saved against a switch. Blocking a config that happens to work is the safe direction here; passing one that does not is #318.

Two things it deliberately does **not** do:

- It never looks at parameter *values*. A switch an operator has turned off is the mechanism working, and an archive must not be blocked because someone is using the lever.
- It fails rather than passes when it cannot reach the backend. "Could not look" must never read as "looks fine" - that is the exact shape of the gap it exists to end.

### What a pull request is told

The archive preflight cannot run on a pull request: a flag added there is not published anywhere yet, by definition, and never should be.
So `scripts/ci/report-kill-switch-changes.mjs` runs instead, and asserts the half that needs no backend - every catalog enum and `remoteconfig.template.json` declare the same keys, and each parameter ships with a description in its healthy shape: a `BOOLEAN` that is on for a switch, the declared type at the declared baseline for a setting.

The rest is reporting.
A pull request that adds a switch says so in its checks, naming the switch, where it lands automatically, and that production does not.
That is the difference between learning about a new switch at review time and learning about it from a staging archive that failed hours after the merge.

A captain-only parameter is reported under its own heading rather than suppressed, because its instruction is the opposite one: nothing publishes it anywhere, and the next staging archive stops until a captain has.
Excluding it from *publication* is the design; excluding it from the *report* would leave the reviewer reading "this change adds none" about the one parameter that will break the build.

### Publish and verification record

| Project | Published | Template version | Verified |
|---|---|---|---|
| Dev `ascend-f2e4f` | 2026-08-03 | 7 (1 = first publish; 2-3 were the switch exercise below) | Backend read-back: all nine present |
| Staging `ascend-staging-fa7d5` | 2026-08-03 | 2 | Backend read-back: all nine present |
| Production `ascend-prod-9c8f2` | 2026-08-02 | 1 | Backend read-back, parameter by parameter - see below |

The 2026-08-03 dev and staging rows are the manual remediation of #367's three routine switches, read back off the backend rather than off a client.
Both now carry all nine and no longer carry the retired `leaderboard_publishing_enabled`.
Production was not re-read for that remediation and still shows the 2026-08-02 publish of seven; the production archive preflight is what refuses to ship a binary against it while the routine switches are unreachable there.

Client-side verification reads the Firebase SDK's own activation store in the simulator container, `Library/Application Support/Google/RemoteConfig/RemoteConfig.sqlite3`:

```bash
container=$(xcrun simctl get_app_container booted com.TylerPavay.AscendApp.dev data)
sqlite3 "$container/Library/Application Support/Google/RemoteConfig/RemoteConfig.sqlite3" \
  "select key, cast(value as text) from main_active order by key;"
```

`main_active` is what makes `RemoteConfigValue.source` report `.remote`, which is the single condition `FirebaseRemoteFeatureFlagSource.remoteSourcedValues()` requires before a value counts.
A key present there is, by construction, a key the app resolves from the server rather than from `shippedDefault`.
`main_default` must stay empty - Ascend deliberately calls no `setDefaults`, and a non-empty table would mean the `.remote` / `.default` distinction had been destroyed.
The **Remote Flags** screen shows the same thing with a UI, and is the right tool on a TestFlight build where there is no container to read.

**Production read-back, 2026-08-02.** No production client verified this publish, so the backend was read back independently and compared against the code, parameter by parameter. `RemoteFeatureFlag.shippedDefault` is the unconditional `{ true }` - not a per-case switch - so the correct production state is all seven `true`, and that is what came back:

| Parameter | Backend | Type | `shippedDefault` |
|---|---|---|---|
| `leaderboard_publishing_enabled` | `true` | BOOLEAN | `true` |
| `local_data_migrations_enabled` | `true` | BOOLEAN | `true` |
| `public_profile_publishing_enabled` | `true` | BOOLEAN | `true` |
| `workout_cloud_backup_writes_enabled` | `true` | BOOLEAN | `true` |
| `workout_cloud_restore_enabled` | `true` | BOOLEAN | `true` |
| `workout_media_uploads_enabled` | `true` | BOOLEAN | `true` |
| `workout_remote_deletes_enabled` | `true` | BOOLEAN | `true` |

Seven keys in code, seven parameters on the backend, no unrecognised parameters, no `parameterGroups`, no `conditions`, template version 1. Every value matches its `shippedDefault` exactly, which is what makes this publish a no-op for behaviour: production resolves the same answers it resolved yesterday, but now from the server, where they can be changed.

Proving the production *client* resolves `.remote` would mean running a production-configured build, which registers an app instance against the production project - beyond "publishing config is authorised". The archive preflight covers that permanently instead: no production build can be cut while a flag is missing from `ascend-prod-9c8f2`.

### The switch exercise (dev, 2026-08-02)

The console-to-gate chain had never run end to end, because until this publish no parameter existed on any backend to flip.
Exercised on dev with `workout_media_uploads_enabled`:

1. Published with the flag set to `false`. The client resolved `false` on its next launch.
2. The other six stayed `true` - one switch moves one path.
3. Re-running the deploy **refused**, naming the active kill switch, and published only once re-run with `--allow-overwriting-active-kill-switch workout_media_uploads_enabled`.
4. The client returned to `true`.

**Not yet demonstrated: the real-time listener.** Both transitions above were observed after a relaunch, which is the foreground-fetch path. On a foregrounded simulator build the listener did not deliver either change within 60 seconds, in either direction. That is one unexplained observation on one simulator, not an established defect - the `streamFetchInvalidations` connection did open, and a simulator's QUIC handling is not a device's. The claim under "Flipping one" that a running app picks a change up within seconds is therefore **unverified**, and the deferred behaviour of the gates themselves is covered by `AscendAppTests/RemoteFeatureGateTests.swift` rather than by this exercise. Confirm the listener on a real Staging TestFlight device via the Remote Flags screen before relying on it during an incident; a foreground relaunch is the fallback that is known to work.

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
   This reaches every install, including the ones already updated, with no submission and no wait for review - on the next foreground at the latest, and see "Flipping one" for why that is the timing to plan around.
2. **Pause the phased release.**
   This stops the population of affected installs growing.
3. Fix, submit, and re-arm phased release on the new version.
4. Turn the switch back on once the fixed build has rolled out.
   Deferred work drains on its own.

Step 1 first, deliberately: the pause protects users who have not updated yet, the switch protects the ones who have.
