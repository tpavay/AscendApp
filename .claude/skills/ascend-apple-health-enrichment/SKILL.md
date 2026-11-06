---
name: ascend-apple-health-enrichment
description: Use when working on Ascend's Apple Health integration - connecting Health, the stair workout import (ledger, anchor, observer, auto-import), the enrichment service and its bounded retry ledger, what any heart-rate surface may say, or the requested HealthKit read set - and when writing any screen `.task` or service `configure` that touches the workout store, which fires from Home and other feature code far outside the Integrations folder. Covers why enrichment reads Health over a climb's own time window and never touches a foreign workout record, why import is a separate service with its own ledger, why a pass that cannot run must not re-arm, and the bounded-query rules that keep the entry path off the main thread's critical section.
---

# Apple Health: import and enrichment

Ascend ranks stair stepper workouts, it does not track them.
Apple Health does two separate jobs here, and they never share a code path.

- **Enrichment** fills in the heart rate and calories a phone cannot measure, for a climb Ascend already recorded.
  It is the original integration and the rest of this skill unless a heading says otherwise.
- **Import** (1.3.0) brings a stair stepper workout a watch or another app saved to Health in as a climb.
  Apple Health workout import was removed on 2026-08-08 (#437) under the racing-not-tracker positioning and returned as its own reviewed piece.
  Its design, ledger states, announce rules and the overlap hook are in `docs/apple-health-import.md`, owned by `AppleHealthImportService`.

A `Workout` is created by an in-app sensor flow, typed in on the Log a climb screen (`WorkoutSource.manual`, `LoggedClimbService`), or imported (`WorkoutSource.appleHealth`, `AppleHealthImportService`), and nowhere else.
`isInAppSensorWorkout` is what gates enrichment: an imported climb already carries the heart rate and energy of its own workout and is never enriched.
Do not add a second import path behind a flag, a debug toggle, or a "just in case" branch.

## Import in one screen

- Only `stairClimbing` and `stairs` workouts, only on or after the climber's join date, one `HealthWorkoutRecord` per HealthKit workout UUID.
- Steps are the exact number on the workout's own statistics, never a tilde and never a second query over a time window.
  A workout with none imports with zero steps and the Add steps prompt.
- A pass reads from a persisted anchor (`HKAnchoredObjectQueryDescriptor`), files what is new, and imports it when auto-import is on.
  A workout deleted in Health keeps its climb.
- `HKObserverQuery` with immediate background delivery wakes the app for a new workout.
  The completion handler is called on every path and is time-bounded, because HealthKit stops delivering until it is.
- Kill switch `apple_health_import_enabled`.
  Nothing a blocked pass leaves behind is lost: the anchor does not advance while it is off.
- Imported climbs rank only through `ClimbPacePolicy` and the join-date rule (see `ascend-workout-model`): the pass files only workouts from the join date on, and the one-time history backfill (`importHistory(matching:)`, `docs/apple-health-import.md`) files older ones off the boards.

## The boundary that defines this integration

- Enrichment reads **quantity samples over the climb's own `[date, date + duration]` window** - `heartRate` and `activeEnergyBurned` - through `HealthKitMetricsReader.fetchMetrics(during:)`.
  It never queries `HKWorkout`, never matches a foreign workout record to an Ascend climb, and never creates a provenance link.
- That is what keeps it device-agnostic.
  Garmin, Whoop, Polar and Apple Watch all write `heartRate` samples and HealthKit normalises them, so all four arrive through one path.
  What differs between devices is sample density and whether the device wrote anything at all - never the shape of the data.
  Never branch on device, and never name a wearable in copy: naming one tells the other three they are not supported.
- Ascend requests `toShare: []` and never saves an `HKWorkout`.
  `LiveClimbBackgroundSessionService` opens an `HKWorkoutSession` purely to stay alive in the background and calls `discardWorkout()`.
  It opens when the countdown starts, not at GO, so Apple's one-time "Health and Fitness Data" notice for a first workout session lands while the climber is still watching the screen.
- External health data is read-only. Never write back to the source platform.

## The requested read set

`HealthKitAuthorizationClient.readTypes` is exactly four types, read only, with `toShare: []`: `workoutType()`, `stepCount`, `heartRate` and `activeEnergyBurned`.
`enrichmentReadTypes` is the `heartRate` and `activeEnergyBurned` pair on its own, and it is a separate set on purpose.
Enrichment's `connectionState` is judged against that pair, so a climber who connected before import returned is not turned into `revoked` and keeps getting heart rate; `importConnectionState` is the wider check, and answers `neverConnected` until the climber has been shown the sheet for the workout types.
A type Ascend requests but never uses is a permission the climber cannot meaningfully refuse (#353), which is why `flightsClimbed` was dropped from the request: nothing reads it, so a type joins the set only with the code that reads it, the usage string and the disclosures in the same change.
`basalEnergyBurned` stays out.
Adding a read is a privacy-manifest tripwire - see `ascend-privacy-manifest`, and `NSHealthShareUsageDescription` must name every type here (`AppleHealthSurfacesEvidenceTests`).

## One service, one schedule, one ledger

`AppleHealthEnrichmentService` is the single enrichment path.
There is no second coordinator and no second status enum; do not add one.

- Health writes a climb's samples *after* the climb ends, so one attempt at save time answers for nobody.
  `AppleHealthEnrichmentSchedule` is the bounded curve - nine attempts reaching roughly ten hours past the climb, dense early and sparse late - plus a 72-hour eligibility window for a climb the curve never covered (one hydrated onto a fresh device, one whose ledger entry was lost).
- `AppleHealthEnrichmentAttemptStore` is the ledger, and eligibility is a **persisted absolute date**, never a counter with a cooldown.
  Several callers ask about the same climb in the same instant - the save-time pass, the workout detail, an app foreground and the timer itself - and a counter would let three of them spend three attempts on one millisecond.
  An absolute date is unanimous whoever reads it, and it survives relaunch, so a force-quit does not hand out a fresh budget.
  The service reads its curve back off the ledger (`attemptStore.schedule`) rather than holding a second copy.
- One timer serves every tracked climb: it sleeps until the earliest due attempt across all of them, runs one pass, and re-arms.
  Wake-ups are a function of the schedule, not of how many times the climber climbed today.
- **A pass that could not run must not re-arm.** Every reason a pass cannot accomplish anything - a suspended account session, a missing Health connection, the kill switch - is read through `canRunEnrichment` and checked *before* a pass, because a blocked pass leaves every tracked climb still due, so arming off the back of one schedules the next wake-up a second out and keeps doing it.
  That is a spin wearing a schedule's clothes.
  Blocked work is deferred to the next lifecycle event instead: `resumeTracking` runs on authenticated bootstrap and on foreground, and the Integrations card's connect tap refreshes straight after granting.
- A read is exclusive per climb.
  A caller arriving while a read for that climb is in flight joins it and is answered by its outcome, rather than starting a second read that spends a second attempt on the same answer.
- A climb that carries a **live-captured** heart-rate series (a strap paired to Ascend during the session) keeps it.
  That data is first-party and denser than anything a wrist writes afterwards; enrichment still fills calories.

## What the climber is told, and where

Enrichment narrates nothing on the surfaces that celebrate a climb.
The Live Climb completion summary and Workout Detail render the chart when a stored series exists and nothing at all about heart rate when it does not - no heading, no card, no empty state - while the schedule keeps looking underneath.
Workout Detail may still show its remote-series restore state, because that means data exists and is arriving, not that the climb has no heart rate.
Regression coverage: `AscendAppTests/WorkoutDetailHeartRateVisibilityTests.swift`, `AscendAppTests/LiveClimbCompletionSummaryHealthPromptEvidenceTests.swift`.

**The connection has two doors and one flow.**
Settings -> Integrations and the Climb sheet's Connect Health button both open `AppleHealthConnectFlowView` (connect, which opens the iOS sheet at once - there is no permission-guide screen between them, because every extra tap costs a climber - then the Import automatically or Let me choose screen; both screens end in `HealthFlowChrome`'s bottom bar, so the primary button never moves, and only the connect screen draws the close X); Integrations is still the only place that explains revoked or unavailable permissions and the only place a heart-rate check can be asked for by hand.
Do not grow a third door, and do not re-introduce a per-climb status enum for a view to render - the previous narration API (`Phase`, `phase(for:)`, `offersConnectionPrompt`, `FetchResult`, `fetchNow`, `connectAndFetch`) was deleted once every surface that consumed it was.
The card reads `appleHealthConnectionState` and drives `requestAppleHealthAuthorizationIfNeeded` then `refreshPendingEnrichment(isUserInitiated:)`.

Failure copy names nothing the climber owns and never carries an `error.localizedDescription`; the underlying error goes to `AppDiagnosticsRecorder` instead.
A failed query and an empty one are kept apart starting at the read: `HealthKitMetricsReading.fetchMetrics` throws when a query fails and returns an empty `WorkoutMetrics` only when the query succeeded with nothing in it, because an empty answer is a real answer that ends the retry series and a failed query is not.
Reporting the second as the first sends the climber to their own equipment for a failure that was Ascend's.

Only a climber-initiated action writes `lastErrorMessage` - connecting, or a check that passes `isUserInitiated`.
The automatic series stays silent whatever happens to it: Home refreshes enrichment from its `.task`, its tab handler and every foreground, so a message written there would be waiting on a screen the climber opens later with nothing to attach it to.
The same reasoning bounds the `apple_health_integration_changed` lifecycle event, which costs a callable and a Firestore transaction: a completed pass reports the connection state only when it actually changed, and only the climber-initiated authorization path reports unconditionally.

## The kill switch

`apple_health_enrichment_enabled` (`RemoteFeatureFlag.appleHealthEnrichment`) gates enrichment where the work can be *deferred*, so a blocked pass leaves the attempt ledger untouched and the climb resumes its own series when the flag comes back.
While it is off, a hand-requested check refuses in its own words rather than reporting a switched-off read as a wearable that published nothing (`checkRefusalMessage`).
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
- Enrichment has no HealthKit observer and no background delivery, and must not grow one.
  `HKObserverQuery` on heart rate was rejected deliberately: its minimum background frequency is hourly and it would wake the app for every heart-rate sample the phone records.
  The one observer in the app is import's, on the workout type, which fires once per saved workout.
  Every completion handler must be time-bounded - HealthKit does not guarantee they fire, and an unbounded continuation is permanent, not slow.

## Related

- `AppleHealthImportService` is also an `AuthenticatedSessionWorker` in `AutonomousSessionWorkers.all`, for the same reason: it writes climbs on its own schedule and stops its observer on sign-out and deletion.
- Enrichment writes columns; it never changes the store's shape. Import adds one model, `HealthWorkoutRecord` (schema V7). A new stored property is a schema migration - see `ascend-data-migration`.
- Load the `healthkit` skill for Apple Health API work.
- The canonical workout contract, plausibility gate and source-vs-participation split live in `ascend-workout-model`.
- What the climb surfaces - completion summary, workout detail - do with heart rate belongs to `ascend-live-climbs`.
