# Headphone session recovery

How a Live Climb, Just Climb or Routine survives the death of the process that was counting it, and how the climber gets their work back.

## The incident this answers

On 2026-10-23 a production climber started an Empire State Building Live Climb, backgrounded Ascend with Instagram in front, and the Ascend process died about a minute later.
Nothing relaunched it.
The Live Activity kept showing "66 steps, 1:02" for twenty minutes because it never went stale.
The recovery screen led with Resume Live, which restarted counting from the dead draft and silently dropped the 19.5-minute gap, and a 22-minute climb saved as a clean 19:32 First Ascent.
The investigation is `data/ascend-live-climb-background-stall/report.md` in the firstmate home; this document is the contract that replaced the failure.

## The contract, for every mode

Every headphone-motion session runs on the same components, so the contract is implemented once and each mode inherits it.
The regression suite `AscendAppTests/HeadphoneSessionSurvivesProcessDeathTests.swift` proves each clause for Live Climb, Just Climb and Routine separately.

1. **The climb survives the process.**
   `HeadphoneSessionCheckpointer` is the one writer of `ActiveHeadphoneWorkoutDraft` for every mode.
   It owns the two-second draft cadence, the fifteen-second heart-rate cadence, its own one-second timer (so checkpoints continue with no view mounted), and the device diagnostics written on every checkpoint: available memory, free disk, memory warnings since the session started, battery, the `HKWorkoutSession` state and the motion status (`HeadphoneSessionCheckpointDiagnostics`, column `checkpointDiagnosticsData`, schema V5).
   A refused `modelContext.save()` is loud: it records `active_headphone_draft_checkpoint_failed` with the error and the free disk, then writes the whole draft to `ActiveHeadphoneWorkoutDraftFallbackStore` as one atomic JSON file beside the store.
   `ActiveHeadphoneWorkoutDraftStore.activeDraft(in:)` folds any such file back into the row before anybody reads the draft, so a storage-starved phone can never freeze the on-disk record at a stale number.
   Account deletion removes the fallback files with the store.
2. **The process comes back by itself when iOS allows it.**
   `AscendSceneDelegate` reads `UIScene.ConnectionOptions.shouldHandleActiveWorkoutRecovery` (iOS 26, HealthKitUI) on every scene connection and hands a workout-recovery launch to `HeadphoneSessionRelaunchCoordinator`, which reattaches the `HKWorkoutSession` through `LiveClimbBackgroundSessionService.recoverActiveWorkoutSessionIfAvailable()`, reads the draft from `AppModelContainerRegistry`, and restarts the session for its mode in the background with no screen.
   Apple documents this relaunch for a crash.
   Whether a jetsam kill or a reboot triggers it is **not documented and not measured here**: the device test plan in the report's section 8c settles it, and clauses 3 and 4 carry the load when it does not fire.
3. **Resume is automatic and honest on the next foreground.**
   `HeadphoneSessionRecoveryPlanner` is pure: a draft younger than one hour (`ActiveHeadphoneWorkoutDraftStore.maximumCreditableTrackingGap`) is `.autoResume`, anything older is `.prompt`, and the loss reason is named from facts the launch can prove: a system uptime shorter than the gap means the phone was off; the crash reporter's `crashedLastRun` means a crash; memory warnings or under 200 MB headroom at the last checkpoint means iOS closed the app; otherwise unknown (a force-quit and a quiet jetsam are indistinguishable).
   `HeadphoneSessionRecoveryCoordinator.resume` credits the gap as wall clock the way `applyRecoveryStepSync` always did (`creditTrackingGap`), records it as one more interruption in the integrity record, restarts the session, and opens `HeadphoneSessionResumeSheet` over it: how long Ascend was not counting and why, the machine's current steps with Save as the primary action, and Keep counting live second.
   `CMPedometer.queryPedometerData(from:to:)` over the gap is offered as the phone's own estimate when it is non-zero, labelled as the phone's and never as the machine's.
   A draft older than an hour keeps a recovery screen, reordered: machine count and Save first, Resume Live second, Discard last, with the plain-language explanation.
   Nothing defaults the climber into silently dropping a gap any more.
   A draft the climber had already ended (`.stopped`: the process died during the save) is never resumed, automatically or from the screen: it offers Save and Discard only, and a typed machine count is credited at the clock they stopped, with no gap.
   `MainTabView` presents the cover whenever a draft exists and `HeadphoneSessionScreenPresence` says no screen is showing its session, which also covers a session whose screen a tab switch took away and one the HealthKit relaunch restarted in the background.
4. **The Lock Screen is honest.**
   `LiveClimbActivityManager` publishes every live update with a stale date fifteen seconds ahead (`LiveClimbActivityStalenessPolicy`), and the widget draws the stale state as "Ascend stopped counting - Tap to resume", routing through the existing deep link into the resume above.
   Routines run no Live Activity, so nothing on the Lock Screen can lie for them; the two modes that publish one are covered.
5. **The footprint is defended.**
   `AppMemoryPressureMonitor` answers every `didReceiveMemoryWarning`: it counts the warning (the next checkpoint records the count), clears `ImageCache` and `ClimbArtworkMemoryCache`, and runs any registered shedder.
   Home unmounts `GlobeView` for the length of a session (`ActiveSessionFootprintPolicy`), and `AscendAppTests/ActiveSessionFootprintPolicyTests.swift` pins the set of root views allowed to stay mounted under one.
   Measuring the resident footprint with Instruments is the captain's device test, not a simulator result.
6. **Nothing parks a session dead.**
   `CMErrorNotAvailable` and `CMErrorMotionActivityNotAvailable` are dropouts, retried on the stall clock; only the entitlement errors remain fatal, and every `handleSessionError` records `headphone_motion_session_failed`.
7. **Detection within minutes.**
   `live_climb_session_lost` fires once per draft the launch finds (age, steps, duration, last HK state, available memory at the last checkpoint, suspected reason, plan) and `live_climb_session_resumed` when the gap is settled (`gap_seconds` measured, `gap_credited_seconds` actually credited, `gap_source` wall clock, pedometer or machine - `none` when nothing was credited - step delta, action).
   Every `AppDiagnosticsRecorder` event reaches Sentry as a breadcrumb at its own level through `CrashlyticsBreadcrumbSink`.
   `MetricKitExitReporter` forwards each daily `MXAppExitMetric` as `app_exit_metrics`, the only count of background kills iOS offers.
   Every session writes `users/{uid}/attempt_heartbeats/{sessionID}` every sixty seconds (steps, duration, mode, `lastSeenAt` on the server clock, `state: open`), closes it with `state: ended` and the outcome, and the scheduled `flagStalledAttemptHeartbeats` writes `attempt_heartbeat_flags/{uid}__{sessionID}` for any heartbeat silent for five minutes before its end, then resolves the flag when the session resumes or ends.
   The heartbeat document is owner-only in `firestore.rules` (`tests/firebase-rules/attempt-heartbeat-contract.test.mjs`); the flags are server-only.
   A heartbeat is a Firestore write, so on a persistent-cache process whose volume has reached the low-disk floor `FirestoreDiskGuard` refuses it before the SDK is asked and the checkpointer records `attempt_heartbeat_publish_failed`; nothing is queued (`docs/firestore-disk-full-guard.md`).

## Kill switches

`headphone_session_auto_resume_enabled` off turns every recovered draft into the prompt, which credits nothing until the climber acts.
`attempt_heartbeats_enabled` off stops the heartbeat writes; nothing is queued and the climb is untouched.
Both are in `docs/remote-config-kill-switches.md`.

## What the simulator cannot prove

The suite drives the real view models with the sensor faked.
It cannot show headphone motion, a real jetsam, a real `HKWorkoutSession` relaunch, a reboot, or device memory figures.
The report's section 8c is the device test plan for those: a baseline climb locked for three minutes, a memory-pressure run with Instagram in front, a forced `SIGKILL` from the Mac with and without the relaunch handler, a fresh install with Health declined, and a low-storage run with the Debug diagnostics log open.

## Querying what the server saw

```bash
node scripts/firestore-query.mjs collection attempt_heartbeat_flags --env prod --confirm-production
node scripts/firestore-query.mjs subcollection users/<uid>/attempt_heartbeats --env prod --confirm-production
```

A flag with `resolvedAt: null` is a session the phone stopped counting and has not come back to; `resolution: resumed` carries the steps and duration it came back with.
