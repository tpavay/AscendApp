---
name: ascend-workout-import
description: Use when working on Ascend workout imports - Apple Health / HealthKit import, the import facade, auto-import opt-in and activation timestamp, the latest-unseen review flow, background freshness and HealthKit observers, or external provider provenance - and when writing any screen `.task` or coordinator `configure` that touches the workout store, which fires from Home and other feature code far outside the Integrations folder. Covers why enriched Live Climbs never surface for review, how external data enters the canonical store, and the bounded-query and cancellation rules that keep the entry path off the main thread's critical section.
---

# Import UX

External workout imports exist because Ascend partly serves as a logger - alongside the two in-app workout origins (Live Climbs captured via headphone motion, and manual entries typed by the user), users may want to bring in Apple Health stair workouts or future wearable data. The principles below govern how external data enters the system safely.

## Data integrity (applies to all workout origins)
- A single canonical `Workout` is the only persisted form. Every origin - manual entry, headphone-motion Live Climbs, Apple Health imports, future wearables - converges to it. Source-specific provenance is recorded on a separate provenance type, never as fields on the workout itself. See `ascend-workout-model` for the full source vs participation contract.
- All *external imports* flow through a single import facade. Provider-specific code lives behind that facade; UI and downstream code never speak directly to a provider. (Manual entry and Live Climb capture have their own in-app creation paths - they don't go through the import facade.)
- Plausibility validation runs at the entry boundary - bad data (implausible step rates, impossible durations) never enters the canonical store. The gate is the same for manual save, edit, external import, and Live Climb completion.

## External health sources (e.g. Apple Health)
- External health data is read-only. Never write back to the source platform.
- Apple Health permission grant doubles as auto-import opt-in: when the user grants access, auto-import turns on automatically, with clear inline guidance about how to disable it later. We never sync without permission, but we treat granted permission as "the user wants their new workouts to flow in."
- An activation timestamp is recorded at the moment auto-import turns on (i.e., when the user grants permission). Only workouts finished *after* that moment flow in automatically. Pre-existing history stays in the manual review flow until the user explicitly imports it - granting permission shouldn't dump weeks of old data on them.
- Auto-imported workouts use a **latest-unseen review model**, never a backlog queue. Surface only the newest unseen workout for review; if a newer one arrives mid-review, replace; advance the watermark when review completes so older ones never resurface.
- Auto-import setup is handled inline in the import flow - don't require the user to navigate to settings to set up a provider for the first time.
- Apple Health workouts that enrich an existing Live Climb (per the enrichment rules in `ascend-live-climbs`) **do not** surface in the review flow or in the manual import list - regardless of auto-import setting. Enrichment is silent; the user is never asked to confirm imported data on a Live Climb.

## Review semantics
- Reviewing an auto-imported workout is a *cleanup pass on an already-saved record* - semantically distinct from creating a new workout. UI affordances (button labels, dismiss behavior) should reflect that the workout already exists.
- The review surface exists to fix bad step counts on workouts imported from external wearables (Apple Watch step data is frequently wrong for stair-stepper use) and to let the user add notes / media to the imported record. It does not apply to Live Climbs - those have accurate in-app step counts and gather notes / media at the completion summary, not via review.

## Entry-path cost (the ASCEND-IOS-1K rule)
- Nothing reached synchronously from a screen's `.task` or a coordinator's `configure` may run a query whose cost grows with the user's history.
`Workout` carries its heart-rate series inline, so `fetch(FetchDescriptor<Workout>())` materialises the device's entire heart-rate history - it is never a cheap way to answer a question about one workout.
Answering "does this ID still exist?" that way blocked Home for 182 seconds on every entry.
- Identity and dedupe questions go through the bounded queries in `AscendApp/Shared/Repositories/` - `WorkoutExistenceQuery`, `AppleHealthLinkQuery`, `InAppSensorWorkoutQuery` - not through an in-memory index built from the whole store.
`AppleHealthLinkQuery` checks the `WorkoutSourceLink` row *and* the legacy `Workout.healthKitUUID`, because the Firestore restore path writes the UUID without creating a link; dropping either check duplicates imports.
`InAppSensorWorkoutQuery` is bounded by in-app session count rather than constant, on purpose - its doc comment states why narrowing further would change enrichment semantics.
- Work that is unbounded by nature (the legacy source-link backfill, a large Apple Health import) runs in a cancellable batched task off the synchronous path, saving each batch before the next starts and setting the completion flag only at the end, so an interruption costs an idempotent re-walk rather than lost or skipped rows.
- Home stays interactive while a backfill lands and says so: `HomeImportProgressBar` reports the remaining session count off `WorkoutImportCoordinator.remainingImportCount` / `totalImportCount`.
A single arriving workout is not narrated.

## Refresh ownership and cancellation
- Concurrent refreshes coalesce onto one shared unstructured task, so it does not inherit cancellation for free - `refreshPendingImports` wires it up explicitly.
- Only the caller that *started* a pass may cancel it. A caller that merely joined stops waiting without stopping the pass, so dismissing the import sheet never kills the backfill Home started.
- Cancellation is always safe: imported workouts are saved individually and the next entry resumes from there.

## Background freshness
- Prefer system-provided background delivery (e.g. HealthKit observers) when available; fall back to launch/foreground incremental refresh.
- Observer callbacks must be serialized through the import facade - a callback wakes the pipeline; the pipeline owns the actual fetch.
- Every HealthKit completion handler awaited from the import system must be time-bounded.
HealthKit does not guarantee they fire - `disableBackgroundDelivery` reliably does not on a simulator without Health authorization - and an unbounded continuation is not a slow call but a permanent one: it strands the shared refresh task forever, and a continuation is not a cancellation point.
`HealthKitBackgroundSyncManager` bounds them, which is what makes the cancellation guarantees above true.

## Related
- Import writes rows; it never changes the store's shape. If a new provider needs a new stored property on `Workout`, that is a schema migration - see `ascend-data-migration`.
- Load the `healthkit` skill for Apple Health API work.
- Adding a new HealthKit metric read is a privacy-manifest tripwire - see `ascend-privacy-manifest`.
