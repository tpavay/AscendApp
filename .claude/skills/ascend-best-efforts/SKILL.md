---
name: ascend-best-efforts
description: Use when working on Ascend Best Efforts or the Progress surfaces - personal records, the record book, per-metric detail and progression charts, weighted loadout records, timeline-segment efforts, the Best Effort ranking cache, or trend surfaces. Covers which metrics are eligible, how the derived cache is rebuilt, and record-book display direction.
paths:
  - AscendApp/Features/Progress/**
---

# Best Efforts Architecture

## Achievement model
- Workouts are the source of truth. Best Efforts are *derived* data - recomputed from workout history, never authored directly.
- Best Effort metrics are stepper-specific and step-first: most steps, longest climb, highest average SPM, sampled time windows, fastest step targets. Don't add floors-based Best Efforts unless product explicitly changes direction.
- Weighted Best Efforts split by exact loadout (e.g. `20 lb Vest` is a different record than `20 lb Vest + 5 lb each Ankle`). Different load configurations = different records.
- Timeline-segment efforts (rolling-window, fastest-segment) require real sampled progress data from Live Climbs. A workout with no sampled progress - a total-only row stored before #437, when Ascend still accepted manual entries and Apple Health imports - contributes *whole-workout* efforts but never segment efforts.
- **A climb typed in (or imported) has no split curve, so its *fastest N steps* record is prorated: `duration x N / steps`, and only when the climb had at least N steps.** The record carries the climb's `ClimbOrigin`, and every surface that shows it draws `ClimbOriginMark` beside it so a prorated time never reads as a split. *Most steps in a time window* stays live-only.
- **A climb the pace check kept off the leaderboards (`Workout.exceedsPaceCeiling`) holds no Best Effort at all.** The test is the pace, not `leaderboardStatus`: a climb excluded for another reason still earns the personal records it is allowed to. See `ClimbPacePolicy`.

## Caching
- Best Effort rankings are persisted as a derived cache. Views read cheap cache lookups; they don't recompute rankings from raw workouts inside `body`. The cache is rebuilt after workout mutations (create / edit / delete) and during startup if the persisted signature is stale.
- Staleness is keyed on the workouts and on `BestEffortCacheStore.currentVersion`, never on the derivation code itself, so changing how an effort is computed leaves existing installs serving values the old logic produced. Any change to effort derivation - including upstream progress-timeline math - must bump `currentVersion` in the same change, which invalidates the persisted cache and rebuilds it on next launch.

## Display direction
- Progress surfaces show Best Efforts as a **record book**, not a dashboard. Each metric appears once with its current best; depth (progression chart, history) lives on the per-metric detail screen. Don't ship filter-heavy comparison surfaces as the default.
- Trend surfaces are insight-first: compare volume / pace / consistency / time against the previous matching period. Show one chart at a time, not a stack of every possible metric.
- Reserve full achievement sentences (e.g. *"2nd fastest 3,000 steps all-time"*) for surfaces where the effort appears out of record-category context - workout list, workout summary, Live Climb completion, share cards.

## Related
- `BestEffortCacheEntry` and `BestEffortCacheMetadata` are `@Model` types, so changing what they persist is a schema migration, not a cache-version bump - see `ascend-data-migration`.
- Achievement motif vocabulary (laurels vs crowns) lives in `ascend-design-system`.
