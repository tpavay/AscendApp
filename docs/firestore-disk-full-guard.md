# Firestore on a full phone: the disk-full guard

Owner of the rule that Firestore's on-device cache never gets to abort an Ascend process.
`FirestoreDiskPolicy` holds the numbers, `FirestoreDiskGuard` holds the process state, and `FirestoreDiskFullSurvivalTests` holds the proof.

## The incident

On 2026-10-23 a climber's Empire State Live Climb stopped counting 39 seconds after GO.
Her phone's crash report shows the process killed by Firestore's own `HARD_ASSERT` in `LevelDbTransaction::Commit()` (`leveldb_transaction.cc:218` in the pinned 11.15.0) when the SDK's on-device LevelDB cache could not write to disk, on the evidence a volume with no free blocks.
The write was a routine live-leaderboard read: `LiveClimbSessionViewModel.refreshReplayLeaderboardIfNeeded` issues six server reads every five seconds, each read is a one-shot listen, and each listen allocates a target inside a LevelDB transaction.
The step counter, the clock, the draft checkpointer and the Live Activity all lived in that process.
Both crash reporters ran their handlers and neither delivered, because each has to create a report file at crash time on the same full volume.
The full investigation, with the symbolicated stack and the headless reproduction, is the scout report this guard was built from.

The assertion is unchanged on firebase-ios-sdk `main`; the maintainers closed the disk-full report (#6727) as a known limitation and advise exactly what this guard does: watch free space and run a memory cache when it is low.

## What writes LevelDB

Everything.
A Firestore read as much as a write: `LocalStore::AllocateTarget` and `ReleaseTarget` on every listen (a `getDocument(s)` is a one-shot listen), `WriteLocally` on every `setData`/`updateData`/`delete`, and `Collect garbage` on the SDK's own timer.
Every one of them is a `LevelDbTransaction` whose `Commit()` is asserted, and an empty transaction still appends a record to LevelDB's log.
So "a read" is not safe, and "nothing is syncing" is not safe; only a process with no LevelDB is safe.

## The policy

`AscendApp/Shared/Services/Firestore/FirestoreDiskPolicy.swift`, pure, pinned by `FirestoreDiskPolicyTests`.

| Reading at launch (`statfs`, bytes available to this process) | Cache |
|---|---|
| Below 200 MiB, or unreadable | `MemoryCacheSettings()` - no LevelDB, nothing can abort |
| 200 MiB or more | `PersistentCacheSettings(sizeBytes: 20 MiB)` - bounded so the cache can never be what fills a phone |
| Kill switch off | `PersistentCacheSettings(sizeBytes: 100 MiB)` - the SDK default, 1.2.3 behaviour exactly |

The reading is `statfs` `f_bavail * f_bsize`, the figure LevelDB's own `write(2)` sees.
Apple's `volumeAvailableCapacityForImportantUsage` adds the space iOS would reclaim by purging caches; it is recorded beside the raw figure in every report so an investigation can see both, and never decided on, because a purge is a promise and `ENOSPC` is a fact.

The decision is applied once, in `AscendApp.configureFirebase()`, as the first thing to touch `Firestore.firestore()`: the SDK refuses settings after first use.
The kill-switch seed (`RemoteFeatureFlagService.configure()`) moved up to run immediately before it for that reason.

## The pre-flight gate

A phone with room at launch gets the persistent cache, and the volume can fill during a climb - that is what happened.
So every Firestore operation that writes the cache asks `FirestoreDiskGuard.shared.allowsLocalCacheWrite()` first (a `statfs` read, microseconds):

- `ServerPreferredRead.run`, the one shared server-read path, refuses the read before the SDK is asked, as `ServerReadFailureClass.unreachable`, with no quiet retry (there is no stream to wait for) and no cache fallback (a cache read is a LevelDB transaction too).
  The live board takes its existing "fetch failed, keep counting" branch (`leaderboardFetchFailed`), and every other caller its unreachable branch.
- `WorkoutSyncCoordinator.processPendingWorkouts` defers the whole pass exactly as a kill switch does: nothing attempted, counted or marked, the outbox and the tombstones untouched, and the next trigger after the phone has room runs it.

A memory-cache process answers yes without reading the disk; it has nothing to protect.

## What the gate does not reach

The gate covers the heaviest path Ascend has (a Live Climb's six reads every five seconds) and the automatic writes.
It does not cover the SDK's own garbage-collection transaction (first about a minute after start, then every five minutes), the single Home listener (`HomeTodayActivityService`), or the one-record user-initiated writes (`ProfileRepository`, `UserDataRepository`, `ModerationRepository`, `FeedbackService`).
A persistent-cache process whose volume fills mid-session is therefore protected on the paths that run during a climb and still exposed on those.
The complete answer is a memory cache always, which the report left as a product decision for the captain; the policy is one line away from it (`cacheMode` returning `.memory`).
Measure first: `docs/firestore-disk-full-guard.md` is where that measurement belongs when it is taken.

Deferred to the follow-up after https://github.com/tpavay/AscendApp/pull/655 lands, because they live in its files: gating `FirestoreAttemptHeartbeatRepository.publish` (one `setData(merge:)` per minute per session) and extending `MetricKitExitReporter` with `MXDiagnosticPayload` so the assertion text itself reaches a report.

## The kill switch

`firestore_memory_cache_on_low_disk_enabled`, default on, catalogued in `RemoteFeatureFlag.firestoreMemoryCacheOnLowDisk` and documented with the others in `docs/remote-config-kill-switches.md`.
Off: the SDK's default persistent cache at the next cold launch, and the gate disarmed immediately on every running install - the 1.2.3 behaviour, crash included.
It exists because the policy changes how persisted data is shaped at startup, and an iOS binary cannot be rolled back.

Merging to `develop` publishes it to dev and staging automatically.
Production is a publish by hand before the production archive's preflight will pass:

```bash
cd scripts && npm run remoteconfig:publish-new:production -- --apply
```

## Visibility

Two things are recorded so the next investigation can see how full the phone was instead of inferring it from a crash report that never arrived:

- `AppDiagnosticsRecorder` event `firestore_low_disk_mode` (`trigger`, `cache_mode`, `free_bytes`, `important_free_bytes`), once when the launch decision is memory and once on the first refused operation of a persistent process; and `workout_sync_deferred_low_disk` once per run of deferrals.
- Telemetry event `firestore_low_disk_mode` with the same fields (`FirestoreDiskAnalyticsEvent`), classified in `AscendAppTests/PrivacyAnalyticsClassification.md`.

And the crash channel a full phone cannot silence: `options.enableMetricKit = true` in `SentryOptionsFactory`, pinned by `SentryDiagnosticsConfigurationTests.metricKitCrashDiagnosticsAreOn`.
iOS writes `MXCrashDiagnostic` into system-reserved space from the same data as its own `.ips` and hands it to the app on the next launch; the SDK turns it into an unhandled event with the call-stack tree.
Both existing crash handlers stay; this is a third delivery path, not a third reporter (`docs/sentry-setup.md`).

## The laboratory

`AscendAppTests/FirestoreDiskFullLab.swift` and `AscendAppTests/FirestoreDiskFullSurvivalTests.swift`.

The simulator shares the Mac's volume and cannot fill it, so the volume Firestore writes to is swapped: `scripts/ci/run-ios-test-passes.sh` creates an 8 MB APFS image (`hdiutil create -size 8m -fs APFS`), attaches it with `-nobrowse` at a fresh path per run, and exports its mount point as `TEST_RUNNER_ASCEND_DISKFULL_MOUNT`, which the test host sees as `ASCEND_DISKFULL_MOUNT`.
The lab points a dedicated `FirebaseApp`'s `Library/Application Support/firestore/<app>` into the image through a symlink, disables the network, and fills the image until a one-byte write is refused.
The 8 MB image is under the 200 MiB floor even when empty, so `LabVolumeReader` shifts a roomy reading above the floor and leaves a full reading as it is; what is under test is the real SDK on a real full volume and the real gate reading that same volume.

Two tests, through the real `FirestoreLiveReplayLeaderboardRepository` and `LiveReplayLeaderboardService.refreshIfNeeded`:

1. Room at launch, persistent cache, the volume fills mid-climb. Before the guard this aborted the host in `LevelDbTransaction::Commit()`; now `leaderboardFetchFailed` is true, `phase` stays `.recording`, and the process is alive.
2. Full at launch: the process gets a memory cache, forty new listens and ten refreshes fail offline and nothing else.

The suite skips itself without the image and is a named pass in `scripts/ci/plan-test-passes.mjs`, so a skipped suite fails its pass rather than counting as green; `scripts/test/firestore-disk-full-lab-contract.test.mjs` holds the runner, the Swift key and the planner to each other.
It rides in a host of its own because what it tests is whether the host survives.

To run it locally, let the runner attach the image (`./scripts/ci/run-ios-test-passes.sh <simulator-udid>`), or attach one yourself and export the variable before the documented `xcodebuild ... test` command.
