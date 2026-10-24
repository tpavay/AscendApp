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

The assertion is unchanged on firebase-ios-sdk `main`; the maintainers closed the disk-full report (#6727) as a known limitation and advise watching free space and running a memory cache. Ascend runs the memory cache always.

## What writes LevelDB

Everything.
A Firestore read as much as a write: `LocalStore::AllocateTarget` and `ReleaseTarget` on every listen (a `getDocument(s)` is a one-shot listen), `WriteLocally` on every `setData`/`updateData`/`delete`, and `Collect garbage` on the SDK's own timer.
Every one of them is a `LevelDbTransaction` whose `Commit()` is asserted, and an empty transaction still appends a record to LevelDB's log.
So "a read" is not safe, and "nothing is syncing" is not safe; only a process with no LevelDB is safe.

## The policy

`AscendApp/Shared/Services/Firestore/FirestoreDiskPolicy.swift`, pure, pinned by `FirestoreDiskPolicyTests`.

Ascend runs Firestore on `MemoryCacheSettings()` in every process.
A memory cache never opens LevelDB, so the commit assertion is unreachable: there is no transaction for it to fire in, however full the phone is or becomes during a climb.

| `firestore_memory_cache_enabled` | Reading at launch (`statfs`, bytes available to this process) | Cache |
|---|---|---|
| On (shipped) | Anything | `MemoryCacheSettings()` - no LevelDB, nothing can abort |
| Off | Below 200 MiB, or unreadable | `MemoryCacheSettings()` |
| Off | 200 MiB or more | `PersistentCacheSettings(sizeBytes: 20 MiB)` - bounded so the cache can never be what fills a phone, and guarded by the pre-flight below |

The reading is `statfs` `f_bavail * f_bsize`, the figure LevelDB's own `write(2)` sees.
Apple's `volumeAvailableCapacityForImportantUsage` adds the space iOS would reclaim by purging caches; it is recorded beside the raw figure in every report so an investigation can see both, and never decided on, because a purge is a promise and `ENOSPC` is a fact.

The decision is applied once, in `AscendApp.configureFirebase()`, as the first thing to touch `Firestore.firestore()`: the SDK refuses settings after first use.
The kill-switch seed (`RemoteFeatureFlagService.configure()`) moved up to run immediately before it for that reason.
`FirestoreDiskPolicyTests.theAppsFirestoreWasConfiguredWithTheMemoryCache` reads the app's own Firestore settings in the test host after that launch.

## What the memory cache covers

Everything that writes LevelDB in a persistent process, with no list to keep current:

- the Home feed listener (`HomeTodayActivityService`), which stays attached under a Just Climb pushed from Home and writes every server-published feed update into the cache;
- the SDK's own garbage-collection transaction (first about a minute after start, then every five minutes);
- every read that does not go through `ServerPreferredRead` - `getDocuments(source: .default)` in `FirestoreLiveReplayLeaderboardRepository` paging, cloud restore in `WorkoutRemoteRepository`, `ProfileRepository`, `UserDataRepository`, `PeriodRecapRepository`, `AthleteLookRepository` and `LeaderboardResultsRepository`;
- the one-record user-initiated writes (`ProfileRepository`, `UserDataRepository`, `ModerationRepository`, `FeedbackService`).

What the memory cache costs is the device's copy: a cold launch re-reads from the server what a persistent cache would have answered locally, and a read that falls back to the cache finds only what this process has already seen.
Ascend reads from the server by design and keeps its own outbox in SwiftData, so nothing a climber recorded depends on that copy.
It also means an empty cache read proves nothing after a relaunch: `ModerationStore` trusts an empty cached block list on a cold launch that cannot reach the server only when the process runs the persistent cache, so under the memory cache that launch stays masked - every other climber's identity hidden - until the block list reaches the server.

## The pre-flight gate

Defense in depth, for a process the kill switch put on the persistent cache: it had room at launch and the volume can fill during a climb - that is what happened.
So the operations Ascend owns ask `FirestoreDiskGuard.shared.localCacheWriteRefusal()` first (a `statfs` read, microseconds):

- `ServerPreferredRead.run`, the one shared server-read path, refuses the read before the SDK is asked, as `ServerReadFailureClass.unreachable`, with no quiet retry (there is no stream to wait for) and no cache fallback (a cache read is a LevelDB transaction too).
  The live board takes its existing "fetch failed, keep counting" branch (`leaderboardFetchFailed`), and every other caller its unreachable branch.
  The refusal carries the reading it was made on.
- `WorkoutSyncCoordinator.processPendingWorkouts` defers the whole pass exactly as a kill switch does: nothing attempted, counted or marked, the outbox and the tombstones untouched, and the next trigger after the phone has room runs it.
- `FirestoreAttemptHeartbeatRepository.publish`, the sixty-second liveness heartbeat of a headphone session (`docs/headphone-session-recovery.md`), is refused before `setData(merge:)` is asked.
  The checkpointer records it as `attempt_heartbeat_publish_failed` with the other publish failures and the climb keeps counting; a heartbeat is a report about now, so nothing is queued and the next due heartbeat after the phone has room is simply sent.

A memory-cache process answers without reading the disk; it has nothing to protect.
The gate cannot reach anything in the list above, so a persistent process whose volume fills mid-session is still exposed on those paths; that exposure is what the kill switch's off position costs, and why it ships on.

The assertion text itself is recorded too: `MetricKitExitReporter` subscribes to `MXDiagnosticPayload` and reduces every `crashDiagnostics[]` entry to an `AppCrashDiagnosticSummary` (Visibility, below), and the launch that finds a draft names the loss from the last checkpoint's free-disk reading (`docs/headphone-session-recovery.md`).

## The kill switch

`firestore_memory_cache_enabled`, default on, catalogued in `RemoteFeatureFlag.firestoreMemoryCache` and documented with the others in `docs/remote-config-kill-switches.md`.
Off, from the next cold launch, a process that starts with at least 200 MiB free runs the bounded persistent cache and the pre-flight guards it; the paths the gate cannot reach can then abort a full phone again.
It exists because the cache decides how Firestore persists at startup, and an iOS binary cannot be rolled back: if the memory cache turns out to cost more than it saves, the persistent cache comes back without a release.
Kill switches ship on and are pulled off, which is why the switch names the memory cache rather than the persistent one.

Merging to `develop` publishes it to dev and staging automatically.
Production is a publish by hand before the production archive's preflight will pass:

```bash
cd scripts && npm run remoteconfig:publish-new:production -- --apply
```

## Visibility

Two things are recorded so the next investigation can see how full the phone was instead of inferring it from a crash report that never arrived:

- `AppDiagnosticsRecorder` event `firestore_low_disk_mode` (`trigger`, `cache_mode`, `free_bytes`, `important_free_bytes`), once when the volume is under the floor at launch (`launch_low_disk`) and once on the first refused operation of a persistent process (`read_gate`); and `workout_sync_deferred_low_disk` (with `free_bytes`) once per run of deferrals.
  The launch decision is taken before telemetry is configured, so `FirestoreDiskGuard` holds the launch report until `AscendApp.init` calls `reportLaunchDecision()` right after `TelemetryManager.shared.configure()`; a report made earlier would be dropped.
- Telemetry event `firestore_low_disk_mode` with the same fields (`FirestoreDiskAnalyticsEvent`), classified in `AscendAppTests/PrivacyAnalyticsClassification.md`.

And the crash channel a full phone cannot silence: `options.enableMetricKit = true` in `SentryOptionsFactory`, pinned by `SentryDiagnosticsConfigurationTests.metricKitCrashDiagnosticsAreOn`.
iOS writes `MXCrashDiagnostic` into system-reserved space from the same data as its own `.ips` and hands it to the app on the next launch; the SDK turns it into an unhandled event with the call-stack tree.
Both existing crash handlers stay; this is a third delivery path, not a third reporter (`docs/sentry-setup.md`).
Sentry 9.18 converts the call-stack tree and leaves out `exceptionReason`, the one string that names the failing assertion and its `errno`, so `MetricKitExitReporter.didReceive(_: [MXDiagnosticPayload])` records it itself: each `MXCrashDiagnostic` becomes an `AppCrashDiagnosticSummary`, sent once as the analytics event `app_crash_diagnostic` (exception name, class and the first 100 characters of the composed message, termination reason, signal, Mach exception type and code, whether a virtual-memory region was attached, the build and OS from the diagnostic's metadata, the payload's time range), as the error-level diagnostic `app_crash_diagnostic_received` that `CrashlyticsBreadcrumbSink` turns into a Sentry breadcrumb, and as one Sentry message event (`TelemetryManager.recordMessage`, tag `ascend_error_code: metrickit_crash_diagnostic`) carrying the whole text, so `message:"No space left on device"` finds the next one.
`CrashDiagnosticReportLedger` keeps the fingerprints already reported in `UserDefaults`, bounded to 64, so a payload MetricKit redelivers or replays is reported once; `AscendAppTests/MetricKitCrashDiagnosticTests.swift` holds the record, the message, the fingerprint and the dedupe.

## The laboratory

`AscendAppTests/FirestoreDiskFullLab.swift` and `AscendAppTests/FirestoreDiskFullSurvivalTests.swift`.

The simulator shares the Mac's volume and cannot fill it, so the volume Firestore writes to is swapped: `scripts/ci/attach-disk-full-lab.sh` creates an 8 MB APFS image (`hdiutil create -size 8m -fs APFS`) in a fresh `mktemp -d` directory under `$RUNNER_TEMP` - out of the uploaded `build-logs/` - and attaches it with `-nobrowse`; `scripts/ci/run-ios-test-passes.sh` exports its mount point as `TEST_RUNNER_ASCEND_DISKFULL_MOUNT`, which the test host sees as `ASCEND_DISKFULL_MOUNT`.
The lab points a dedicated `FirebaseApp`'s `Library/Application Support/firestore/<app>` into the image through a symlink, disables the network, and fills the image until a one-byte write is refused.
The 8 MB image is under the 200 MiB floor even when empty, so `LabVolumeReader` shifts a roomy reading above the floor and leaves a full reading as it is; what is under test is the real SDK on a real full volume and the real gate reading that same volume.

Two tests, through the real `FirestoreLiveReplayLeaderboardRepository` and `LiveReplayLeaderboardService.refreshIfNeeded`:

1. The kill switch off, room at launch, persistent cache, the volume fills mid-climb. Before the guard this aborted the host in `LevelDbTransaction::Commit()`; now `leaderboardFetchFailed` is true, `phase` stays `.recording`, and the process is alive.
2. The shipped memory cache on a full volume: forty new listens and ten refreshes fail offline and nothing else.

The suite skips itself without the image and is a named pass in `scripts/ci/plan-test-passes.mjs`, so a skipped suite fails its pass rather than counting as green; `scripts/test/firestore-disk-full-lab-contract.test.mjs` runs the attach step on a Mac and checks the volume it mounts, and holds the planner to naming the suite.
It rides in a host of its own because what it tests is whether the host survives.

To run it locally, let the runner attach the image (`./scripts/ci/run-ios-test-passes.sh <simulator-udid>`), or attach one yourself and export the variable before the documented `xcodebuild ... test` command.
