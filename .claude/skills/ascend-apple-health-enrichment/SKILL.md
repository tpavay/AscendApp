---
name: ascend-apple-health-enrichment
description: Use when working on Ascend's Apple Health integration - connecting Health, the enrichment service and its bounded retry ledger, the heart-rate phases every surface renders, or the requested HealthKit read set - and when writing any screen `.task` or service `configure` that touches the workout store, which fires from Home and other feature code far outside the Integrations folder. Covers why Ascend reads Health over a climb's own time window and never touches a foreign workout record, why a pass that cannot run must not re-arm, and the bounded-query rules that keep the entry path off the main thread's critical section.
---

# Apple Health enrichment

Ascend is a racing app, not a tracker.
It does not import workouts and it has no manual entry: **every `Workout` is created by an in-app sensor flow** (Live Climbs and routines captured via headphone motion).
Apple Health does exactly one job - it fills in the heart rate and calories a phone cannot measure, for a climb Ascend already recorded.

Manual logging and Apple Health workout import were removed on 2026-08-08 (#437).
Do not reintroduce either behind a flag, a debug toggle, or a "just in case" path.
`WorkoutSource.manual` and `.appleHealth` survive only because older stored rows carry those raw values; nothing writes them.

## The boundary that defines this integration

- Enrichment reads **quantity samples over the climb's own `[date, date + duration]` window** - `heartRate` and `activeEnergyBurned` - through `HealthKitMetricsReader.fetchMetrics(during:)`.
  It never queries `HKWorkout`, never matches a foreign workout record to an Ascend climb, and never creates a provenance link.
- That is what keeps it device-agnostic.
  Garmin, Whoop, Polar and Apple Watch all write `heartRate` samples and HealthKit normalises them, so all four arrive through one path.
  What differs between devices is sample density and whether the device wrote anything at all - never the shape of the data.
  Never branch on device, and never name a wearable in copy: naming one tells the other three they are not supported.
- Ascend requests `toShare: []` and never saves an `HKWorkout`.
  `LiveClimbBackgroundSessionService` opens an `HKWorkoutSession` purely to stay alive in the background and calls `discardWorkout()`.
- External health data is read-only. Never write back to the source platform.

## The requested read set

`HealthKitAuthorizationClient.readTypes` is exactly `heartRate` and `activeEnergyBurned`, and that list must stay derivable from what enrichment writes onto a climb.
A type Ascend requests but never uses is a permission the climber cannot meaningfully refuse; `workoutType()`, `stepCount` and `basalEnergyBurned` were all requested-and-unused before #437/#353.
Adding a read is a privacy-manifest tripwire - see `ascend-privacy-manifest`.

## One service, one schedule, one ledger

`AppleHealthEnrichmentService` is the single enrichment path.
There is no second coordinator and no second status enum; do not add one.

- Health writes a climb's samples *after* the climb ends, so one attempt at save time answers for nobody.
  `AppleHealthEnrichmentSchedule` is the bounded curve - nine attempts reaching roughly ten hours past the climb, dense early and sparse late - plus a 72-hour eligibility window for a climb the curve never covered (one hydrated onto a fresh device, one whose ledger entry was lost).
- `AppleHealthEnrichmentAttemptStore` is the ledger, and eligibility is a **persisted absolute date**, never a counter with a cooldown.
  Several surfaces ask about the same climb in the same instant - the completion summary, the workout detail, an app foreground and the timer itself - and a counter would let three of them spend three attempts on one millisecond.
  An absolute date is unanimous whoever reads it, and it survives relaunch, so a force-quit does not hand out a fresh budget.
  The service reads its curve back off the ledger (`attemptStore.schedule`) rather than holding a second copy.
- One timer serves every tracked climb: it sleeps until the earliest due attempt across all of them, runs one pass, and re-arms.
  Wake-ups are a function of the schedule, not of how many times the climber climbed today.
- **A pass that could not run must not re-arm.** Every reason a pass cannot accomplish anything - a suspended account session, a missing Health connection, the kill switch - is read through `canRunEnrichment` and checked *before* a pass, because a blocked pass leaves every tracked climb still due, so arming off the back of one schedules the next wake-up a second out and keeps doing it.
  That is a spin wearing a schedule's clothes.
  Blocked work is deferred to the next lifecycle event instead: `resumeTracking` runs on authenticated bootstrap and on foreground, and connecting Health fetches directly.
- A read is exclusive per climb.
  A caller arriving while a read for that climb is in flight joins it and is answered by its outcome, rather than starting a second read that spends a second attempt and clears the `checking` state out from under the first.
- A climb that carries a **live-captured** heart-rate series (a strap paired to Ascend during the session) keeps it.
  That data is first-party and denser than anything a wrist writes afterwards; enrichment still fills calories.

## The phases every surface renders

`AppleHealthEnrichmentService.Phase` is the one answer, and **no case renders blank** - a silent absence was the original bug (#438).
`notApplicable`, `connectionOffered`, `unavailable`, `accessRevoked`, `checking`, `waiting`, `stoppedLooking`, `checksPaused`.
No view may resolve heart-rate availability a second way, and no phase may carry a countdown: `Task.sleep` does not advance while the app is suspended, so a rendered number would be wrong in exactly the case a climber checks it.

`FetchResult` keeps the two honest answers apart for a hand-requested check: `foundNothing` means Ascend read Health and nothing covered this climb, `couldNotLook` means it never read.
Reporting the second as the first is the dishonest blank this service exists to remove.

Resolve the phase once per pass, outside the view body.
`RemoteFeatureFlagStore` is lock-guarded rather than `@Observable`, so reading the kill switch registers no SwiftUI dependency - surfaces that render a phase re-resolve on `.remoteFeatureFlagsDidChange` (`WorkoutDetailView`, `LiveClimbCompletionSummaryView`), which is the shape `MediaUploadBanner` already proved.

## The kill switch

`apple_health_enrichment_enabled` (`RemoteFeatureFlag.appleHealthEnrichment`) gates enrichment where the work can be *deferred*, so a blocked pass leaves the attempt ledger untouched and the climb resumes its own series when the flag comes back.
While it is off, the connect offer is withheld too: asking for Health access would spend a real iOS permission prompt - the one thing a climber can only be asked once - on a benefit the app has been told not to deliver.
See `docs/remote-config-kill-switches.md`.

## Entry-path cost (the ASCEND-IOS-1K rule)

- Nothing reached synchronously from a screen's `.task` or a service's `configure` may run a query whose cost grows with the climber's history.
  `Workout` carries its heart-rate series inline, so `fetch(FetchDescriptor<Workout>())` materialises the device's entire heart-rate history - it is never a cheap way to answer a question about one workout.
  Answering "does this ID still exist?" that way blocked Home for 182 seconds on every entry.
- `AppleHealthEnrichmentService.configure` therefore does no store work at all, and a pass uses `InAppSensorWorkoutQuery` bounded by the eligibility window rather than scanning the store.
- `HomeEntryConfigureBlockingCostTests` is the standing guard: it seeds a large store and asserts `configure` stays an order of magnitude under a full scan.
- Bounded is not the same as free. A climber who never connected Apple Health pays nothing: the connection state is checked **before** any fetch, and any further cheap refusal belongs there too.

## Session ownership and cancellation

- The service is an `AuthenticatedSessionWorker`, registered in `AutonomousSessionWorkers.all`.
  Both ends of a session read that list: account deletion drains it before it empties the store, and sign-out stops it through `AuthenticatedBootstrapCoordinator.endAuthenticatedSession`.
  A self-scheduling writer that survives either one wakes up holding the previous climber's store and work list, and the write it makes is attributed to whoever is signed in when it lands.
  The rest of the deletion contract lives in `ascend-firebase-data` -> Account deletion.
- `cancelInFlightWork` stops the timer, the pass and every in-flight read and empties the tracking set, but **keeps the model context on purpose**.
  Dropping it left the service unable to resume for any owner that adopted it once and does not re-configure, which is how a resolved deletion killed enrichment permanently.
- A view must not cancel the schedule.
  It is account-scoped, not screen-scoped: Home cancelling on `onDisappear` disarmed the whole retry curve on an ordinary tab switch.
- There are no HealthKit observers and no background delivery.
  `HKObserverQuery` plus background delivery was rejected deliberately: heart rate's minimum background frequency is hourly and it would wake the app for every heart-rate sample the phone records.
  If one is ever added, every completion handler must be time-bounded - HealthKit does not guarantee they fire, and an unbounded continuation is permanent, not slow.

## Related

- Enrichment writes columns; it never changes the store's shape. A new stored property is a schema migration - see `ascend-data-migration`.
- Load the `healthkit` skill for Apple Health API work.
- The canonical workout contract, plausibility gate and source-vs-participation split live in `ascend-workout-model`.
- The climb surfaces that render these phases - completion summary, workout detail - belong to `ascend-live-climbs`.
