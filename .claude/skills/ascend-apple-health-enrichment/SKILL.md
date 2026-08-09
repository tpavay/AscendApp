---
name: ascend-apple-health-enrichment
description: Use when working on Ascend's Apple Health integration - connecting Health, the enrichment coordinator and its retry window, the heart-rate recovery states on workout detail, or the requested HealthKit read set - and when writing any screen `.task` or coordinator `configure` that touches the workout store, which fires from Home and other feature code far outside the Integrations folder. Covers why Ascend reads Health over a climb's own time window and never touches a foreign workout record, and the bounded-query and cancellation rules that keep the entry path off the main thread's critical section.
---

# Apple Health enrichment

Ascend is a racing app, not a tracker. It does not import workouts and it has no manual entry: **every `Workout` is created by an in-app sensor flow** (Live Climbs and routines captured via headphone motion). Apple Health does exactly one job - it fills in the heart rate and calories a phone cannot measure, for a climb Ascend already recorded.

Manual logging and Apple Health workout import were removed on 2026-08-08 (#437). Do not reintroduce either behind a flag, a debug toggle, or a "just in case" path. `WorkoutSource.manual` and `.appleHealth` survive only because older stored rows carry those raw values; nothing writes them.

## The boundary that defines this integration

- Enrichment reads **quantity samples over the climb's own `[date, date + duration]` window** - `heartRate` and `activeEnergyBurned` - through `HealthKitMetricsReader.fetchMetrics(during:)`. It never queries `HKWorkout`, never matches a foreign workout record to an Ascend climb, and never creates a provenance link.
- That is what keeps it device-agnostic. Garmin, Whoop, Polar and Apple Watch all write `heartRate` samples and HealthKit normalises them, so all four arrive through one path. What differs between devices is sample density and whether the device wrote anything at all - never the shape of the data.
- Ascend requests `toShare: []` and never saves an `HKWorkout`. `LiveClimbBackgroundSessionService` opens an `HKWorkoutSession` purely to stay alive in the background and calls `discardWorkout()`.
- External health data is read-only. Never write back to the source platform.

## The requested read set

`HealthKitAuthorizationClient.readTypes` is exactly `heartRate` and `activeEnergyBurned`, and that list must stay derivable from what enrichment writes onto a climb. A type Ascend requests but never uses is a permission the climber cannot meaningfully refuse; `workoutType()`, `stepCount` and `basalEnergyBurned` were all requested-and-unused before #437/#353. Adding a read is a privacy-manifest tripwire - see `ascend-privacy-manifest`.

## Enrichment timing and the retry window

- Health writes a climb's samples *after* the climb ends, so a single attempt at completion is not enough. `AppleHealthEnrichmentRetryStore` throttles to one attempt per climb per minute and stops asking 72 hours after the climb ended.
- Status is derived, never stored: `notPending` (not an in-app sensor climb), `complete` (heart rate and calories present), `metricsPending` (inside the retry window), `metricsStalled` (past it - the surface says "stopped checking" rather than pretending). The manual Fetch on workout detail passes `force: true` and still works after the window closes.
- A climb that carries a **live-captured** heart-rate series (Bluetooth chest strap during the session) keeps it. Strap data is first-party and more accurate than wrist-derived Health data; enrichment still fills calories.

## Entry-path cost (the ASCEND-IOS-1K rule)

- Nothing reached synchronously from a screen's `.task` or a coordinator's `configure` may run a query whose cost grows with the climber's history. `Workout` carries its heart-rate series inline, so `fetch(FetchDescriptor<Workout>())` materialises the device's entire heart-rate history - it is never a cheap way to answer a question about one workout. Answering "does this ID still exist?" that way blocked Home for 182 seconds on every entry.
- `AppleHealthEnrichmentCoordinator.configure` therefore does no store work at all, and the pass itself uses `InAppSensorWorkoutQuery`, which is bounded by in-app session count rather than by the whole store. Its doc comment states why narrowing further would change enrichment semantics.
- `HomeEntryConfigureBlockingCostTests` is the standing guard: it seeds a large store and asserts `configure` stays an order of magnitude under a full scan.
- Bounded is not the same as free. A climber who never connected Apple Health pays nothing: `connectionState == .connected` is checked **before** the fetch, and any further cheap refusal belongs there too.
- An `.automatic` sweep re-entering within 30 seconds of the last one is refused by `refreshPendingEnrichment` itself, **before the shared task exists**. That placement is load-bearing, not tidiness: a refused sweep that created a task would be a no-op other callers could coalesce onto, so a climber tapping "Check for heart rate now" a moment after a foreground would join it and be answered with silence. A refused sweep must leave nothing to join. Automatic means the app decided - Home mounting, a tab return, a foreground; `.userInitiated` is a climber waiting on an answer and is never throttled. The 30-second floor is sound because the per-climb retry store already refuses a second read inside a minute, so a sweep behind that floor could only re-decode every climb's heart-rate series to conclude there is nothing to do.

## Refresh ownership and cancellation

- Concurrent passes coalesce onto one shared unstructured task, so it does not inherit cancellation for free - `refreshPendingEnrichment` wires it up explicitly.
- Only the caller that *started* a pass may cancel it. A caller that merely joined stops waiting without stopping the pass.
- Cancellation is always safe: a pass saves what it resolved and the next entry resumes.
- The coordinator is an `AuthenticatedSessionWorker`, so a pass refuses to start while account-scoped work is suspended, and account deletion can cancel and drain it. Rationale and the rest of that contract live in `ascend-firebase-data` -> Account deletion.
- There are no HealthKit observers and no background delivery. If you ever add one, every completion handler must be time-bounded: HealthKit does not guarantee they fire, and an unbounded continuation is not a slow call but a permanent one - it strands the shared task forever, and a continuation is not a cancellation point.

## Related

- Enrichment writes columns; it never changes the store's shape. A new stored property is a schema migration - see `ascend-data-migration`.
- Load the `healthkit` skill for Apple Health API work.
- The canonical workout contract, plausibility gate and source-vs-participation split live in `ascend-workout-model`.
