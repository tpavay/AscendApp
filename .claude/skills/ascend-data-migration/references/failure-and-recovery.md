# Failure and recovery

What happens when a migration fails on a stranger's phone.
This describes what the code on `develop` actually does, then what it does not do, because the gaps are the part that gets forgotten.

## The three ways it fails, and what each one does today

### 1. `willMigrate` throws

`AscendMigrationPlan.stashLegacySources` is the only pass that may throw all the way out of `ModelContainer` construction, and it does so deliberately.
Throwing there leaves the store on V1 with the old column intact, which is the only thing that preserves a retry - once the schema step commits, the old column is gone.

So a failure is worth a dead launch, and then it is not.
`WorkoutSourceMigrationStash.maximumAttempts` is 3.
After the third failed attempt the pass stops throwing, keeps whatever it did resolve, and reports the shortfall.
A user with some values unrepaired plus a signal we can see beats a user whose app never opens again.

**The user sees** the launch-failure screen, `AppLaunchFailureView` with `.localDataUnavailable`: "Ascend couldn't load your data." / "Restart the app. If this keeps happening, contact support before reinstalling."

That copy is right about the important thing.
Telling a local-first user to reinstall destroys the container and the records that exist nowhere else.
Keep that instinct in any copy you write here.

### 2. `didMigrate` throws or the process dies mid-write

`applyStashedSourcesReportingFailure` swallows what the write throws, and that is correct rather than lazy.
The schema step has already committed by then, so throwing would cost a launch and buy nothing: the stash still holds every value.

The stash is the unit of completion, not the transaction.
It lives on disk at `URL.applicationSupportDirectory/workout-source-migration-stash.json`, outside the store, precisely so it survives a process that never reached `didMigrate`.
Each page commits before the next is read, so a run interrupted with some pages landed re-enters next launch and finishes the rest; re-applying a page that already landed costs nothing, because a row whose column already matches is skipped.

**SwiftData records the store as V2 as soon as the schema step commits and will never re-enter the stage.**
That is why the retry cannot live in the plan.
It lives in `AscendApp.createModelContainer` -> `finishInterruptedMigrationIfNeeded` -> `AscendMigrationPlan.recoverInterruptedMigrationIfNeeded`, which runs the same write again against the already-migrated store.
A non-empty stash is the marker that the write never landed.

**The user sees** nothing. The app opens, and the repair happens or is retried next launch.

### 3. The container will not open at all

`createModelContainer` catches, records `model_container_creation_failed`, and returns `.failure(.localDataUnavailable)`.

## What is reported, and what is not

| Event | Mirrored to Crashlytics |
|---|---|
| `workout_source_migration_read_failed` | yes |
| `workout_source_migration_write_failed` | yes |
| `workout_source_migration_stash_unreadable` | yes |
| `workout_source_migration_abandoned` | yes |
| `workout_source_migration_recovered` | yes |
| `workout_source_migration_recovery_failed` | yes |
| **`model_container_creation_failed`** | **no** |

The migration's own failures are visible in the field.
Every one carries resolved, unresolved, repaired and failed-attempt counts, so a run that repaired 800 of 900 rows is a different incident from one that never started.

The container failing to open is not visible.
`AppDiagnosticsRecorder` writes it to `UserDefaults` and the unified log and stops there, so the one event that says "a user's local database would not open" stays on that user's device.
The mitigating detail is that `UserDefaults` survives the failure and the relaunch, so the data exists locally and only needs a delivery path.

**This is a known gap, not a decision this skill is describing approvingly.**
If you are already changing this area, say so in the PR rather than leaving it for the next reader to rediscover.

## What can be done for that user afterwards

Nothing remote and automatic, and it is worth being blunt about why.
The failure happens during launch, before the network stack and before Remote Config has fetched anything.
No app in the surveyed evidence set can remotely repair one user's local database; every recovery path that ships anywhere is either automatic (the app decides) or user-initiated (a button).

What is actually achievable for Ascend:

- **The migration diagnostics already reach us**, with counts, so a field failure in the stage itself is diagnosable without a repro.
- **The cloud backup is the real second copy.** Workouts synced to Firestore can be restored; workouts that never synced cannot. That is the boundary of what any support conversation can offer.
- **A support conversation is the last mile.** There is no console button. The diagnostics in `UserDefaults` are the only device-side record, and today nothing delivers them.

## What a hardened version of this looks like

None of this is in scope for a routine schema change, but it is the shape of the work if the failure screen is ever revisited, and each item exists in shipped local-first apps:

- **Mirror the container-open failure**, with the error domain and code, the schema version the binary expects, the version last recorded on the device, the store's size, and free disk space.
- **A schema-version sentinel outside the store.** Write the current version to `UserDefaults` on every successful open; on launch, refuse to open a store recorded as *newer* than this binary knows, and say "Update Ascend" instead of "couldn't load your data". A user restoring an older backup onto a newer store is a real path, and the framework's behaviour there is undocumented.
- **A launch-attempt counter**, cleared on successful readiness and on version change, so a crash-looping device stops retrying and shows a report action instead.
- **A free-disk check before opening**, failing open if the check itself errors, so low storage produces a specific message rather than an obscure migration failure.
- **Actions on the failure screen**: Retry, Send report, and - only when signed in with a cloud backup present - a destructive, confirmed reset. The screen has none today, which is what makes a one-in-a-thousand failure undiagnosable.
- **Partial success as a named outcome.** "Recovered, but some records could not be" is more honest than a binary and lets the app proceed.

Sources for each of these are in `research.md`.
