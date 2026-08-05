---
name: ascend-workout-model
description: Use when working on the canonical Ascend Workout model, or when wiring any new workout origin - manual entry, external import, or sensor capture - into it, which fires from integration and feature code outside the Workouts folder. Covers workout durability and cloud backup, heart-rate sidecar upload/restore and its validation contract, sync state and the sync coordinator, workout source vs participation separation, plausibility validation, workout measurement (steps, duration, SPM, StairMaster level mapping, historical percentile), the integrity gate keeping Live Climb and routine completions exclusive to their live sensor flows, the deprecated base-level/effort-score legacy, and the local-first SwiftData + Firestore contract with the workout schema open/closed rule.
---

# Workout Model

## The canonical integrity gate (referenced by climbs and routines)

Live Climb completions come only from the live headphone-motion attempt flow, and routine completions come only from the live routine flow. Manual entries, external imports, and routine completions cannot progress or complete a Live Climb. Live Climb eligibility is a quality gate, not a backfill.

Passive interpretations of workout history (lifetime step milestones, climb-equivalent badges, collection counts) are *derived* readings - never participation records. They don't make a workout retroactively eligible for any leaderboard.

## Workout Source + Context Architecture

Three distinct concepts. Keep them cleanly separated - don't fold feature-specific data onto the canonical `Workout`.

**`Workout` is the canonical activity** - what the user actually did (date, duration, steps, floors, health metrics, notes, media). It carries enough to describe the session itself, but no feature-specific attribution.

**Source = how the data was captured.** In-app sensor capture (headphone motion, future wearables), external provider imports (Apple Health, future third parties), and manual entry are each their own source kind. Verified-sensor sources are first-class; they aren't external providers because there's no external record to dedupe against. External-provider dedupe + provenance metadata lives on a separate provenance type, never on `Workout` itself.

**Participation = why the workout exists / what it counts toward.** Feature-specific attribution (climb attempt, routine, challenge, future contexts) lives on a separate participation type, never as nullable fields on `Workout`. New features add new participation kinds; they don't add nullable columns to the canonical type. This is the open/closed principle applied to the workout schema.

### Persisted shape and schema versioning
- Enums on `Workout` are stored as raw values, `source` included (`sourceRawValue`, with `source` as a computed accessor). A Codable enum cannot appear in a `#Predicate` - SwiftData rejects it with `unsupportedPredicate` - so a non-raw enum column is unfilterable, which is what forced source filtering to scan the whole store in ASCEND-IOS-1K.
- Everything else about changing that shape - the versioned schema and plan, what lightweight migration silently does to existing rows, and how an interrupted stage recovers - belongs to `ascend-data-migration`. Load it before editing the `@Model`.

### Integrity rules
- Sensor capture (headphone motion, future wearables) lives behind a shared service layer. The step / progress algorithm is pure compute - unit-testable without hardware. Sensor callbacks must run safely off the main thread; UI updates marshal back to main explicitly.
- Plausibility validation runs at the entry boundary - bad data (implausible step rates, impossible durations) never enters the canonical store. The gate is the same for manual save, edit, external import, and Live Climb completion.
  Heart rate has exactly one definition of a usable reading (`WorkoutHeartRatePlausibility`), applied wherever Ascend first writes a sample into its own cache: the live sensor seam, the live capture buffer, and the HealthKit metrics reader.
  Filtering at ingress keeps the stored series, average, and maximum consistent for the life of the workout - an out-of-range summary is replaced from the retained samples instead of being reconciled downstream, and source records are never rewritten, only Ascend's derived copy.

## Workout Durability Architecture

Local-first with cloud backup. SwiftData is the editing surface and source of truth for in-flight UX; Firestore + Storage carry durable backups so a user's history survives reinstalls and crosses devices.

### Identity and storage
- Each workout has *one* durable identity - a stable UUID shared across the local `Workout`, its Firestore document at `users/{uid}/workouts/{workoutId}`, its heart-rate sidecar in Storage, and any associated media. One identity = cleanup and repair flows can act on all resources at once.
- That identity has exactly one document-id spelling: the uppercase UUID string.
  `firestore.rules` rejects any other casing on `users/{uid}/workouts/{workoutId}`, the client builds every workout document reference through `WorkoutDocumentID`, and Admin SDK scripts go through `scripts/lib/workout-document-id.mjs`.
  Mixed casing silently forks one workout into two documents, so restore-time collisions are deduplicated newest-wins and recorded as `workout_backup_case_variant_duplicate`; existing dev/staging twins are merged by `scripts/cleanup-case-variant-workout-ids.mjs` (dry-run by default, production refused).
- Firestore stores the workout's metadata and summary fields (averages, max HR, totals). Large time-series data (heart-rate samples) goes to Storage as a compressed sidecar - never embedded in Firestore documents. Firestore holds only pointers and summaries.
  The sidecar's owner-scoped path is derived in exactly one place (`WorkoutHeartRateStoragePath`) from the same canonical workout id, and a download whose stored reference points anywhere else is rejected rather than followed.
  The pointer also carries integrity metadata (object schema version, compressed byte count, sha256) so a restore can prove the object it fetched is the one the envelope promised.
- A workout is *fully synced* only when every component (Firestore document + Storage sidecar + media uploads) has succeeded. Partial success is not success.

### Sync state
- Per-workout sync *verdict* (owner, last-modified, last-synced, status, last error) lives *on the local `Workout` itself*. `Workout.remoteSyncStatus` is the single answer to "is this climb in the cloud", exposed as `Workout.isSyncedToCloud`.
- The *retry schedule* is a separate model, `WorkoutSyncOutboxEntry`, one row per not-yet-synced workout. Separate because `Workout` carries relationships: freezing its shape would force frozen copies of `WorkoutSourceLink` and `WorkoutParticipation` across two shipped schema versions, where a brand-new model keeps the stage lightweight. Schedule there, verdict on the workout - the two can never disagree.
- Pending remote deletes are tracked on a separate model for the same reason.

### The retry schedule
Seven surfaces call `WorkoutSyncCoordinator`, so three triggers can consume three attempts in the same millisecond. The rules that follow from that, all owned by `WorkoutSyncRetryPolicy` and `WorkoutSyncOutboxEntry` - read their doc comments before changing a number:

- **Eligibility is a persisted absolute date** (`nextEligibleAttemptAt`), never a bare counter, and it survives relaunch. Offsets are coarse (0s to 24h over seven attempts) because Firestore's SDK already retries the transport; this layer decides when a *logical* backup is worth re-offering. Jitter is upward-only, so the no-earlier-than guarantee holds.
- **Only a genuine remote verdict consumes an attempt.** `cancelled` and `offline` never do - charging a tab switch as evidence is how one stuck workout produced 499 events (`WorkoutSyncFailureCategory.consumesAttempt`).
- **Every stop rule is conjunctive with elapsed time.** The series ends only once the schedule is walked *and* the final offset has elapsed; refusals stop automatic attempts only after 3 of them *and* 30 minutes.
- **`permissionDenied` is `refused`, not `malformed`.** A deployable rules defect emits the identical code, so no client-only classifier can call it permanent. It stays re-openable.
- **A stop is re-openable without a release.** The recovery basis is `buildIdentity|workout_sync_recovery_epoch`; when it moves, every stopped workout gets exactly one more automatic attempt, gated by `workout_sync_recovery_reopen_enabled`. Screen appearances and tab switches deliberately do not qualify. `firestore.rules` deploys independently of app releases, so the epoch is the only lever that unsticks a fleet after a rules fix - see `docs/remote-config-kill-switches.md`.
- **A local edit is a new payload revision** and restarts the series; manual retry re-offers the same bytes and deliberately does not.

### The sync surface
- Whether a climb says it is not in the cloud is gated on `Workout.isSyncedToCloud` alone, never on retry machinery (`== .rejected`, a view-local in-flight flag). Both made the warning vanish the moment a climber tapped retry.
- `WorkoutSyncPresentation` is the only thing the row switches on, derived by the coordinator rather than in a view body. The copy is locked - see `ascend-brand-voice`.
- Manual retry is unlimited; only the *automatic* series stops.

### Orchestration
- A single sync coordinator owns all pending remote work. Mutations don't write to Firestore directly - they update local sync state and kick the coordinator.
- Backup is mutation-driven (immediate after each mutation), not deferred to next launch. The coordinator also runs on authenticated bootstrap and foreground repair to recover missed or failed work.
- Ordering: deletes before upserts; Storage sidecars before the Firestore document that references them; overlapping requests coalesced so launch / auth / lifecycle hooks don't produce duplicate remote work.
  Workout deletion is sidecar-first for the same reason - removing the heart-rate object ends active access before the envelope that points at it disappears.
  Stopping a stale client from recreating either record needs revisioned tombstones plus a grace period, which is deliberately a later durability slice, not something this ordering already solves.
- The uploaded document is always derived from the canonical envelope (`FirestoreWorkoutDocument.replacingHeartRateSeries`), never re-assembled field by field. A hand-built copy silently drops every field added since it was written - that is how participations were lost on the heart-rate upload path.
- Media uploads are part of the durability contract. When media changes after upload completion, the workout is re-marked pending and the backup is republished.

### Restore
- Restore is the other half of durability, not a bonus: a clean signed-in device re-downloads the heart-rate sidecar, so an empty local series is authoritative only when the workout's `WorkoutHeartRateRestoreStatus` says it is (`notNeeded` / `ready`).
  Every other status means "not restored yet". Detail-view rendering and the upload path must read that status instead of inferring "this workout has no heart rate" from local emptiness.
- A pending, retrying, or unavailable restore carries the last known sidecar reference forward on the next upsert, so a device that never restored the series cannot orphan it.
  The one exception is a sidecar the server reported as missing: that reference is dropped, because a dangling pointer would fail every other clean device's restore forever.
- A downloaded sidecar is validated before it is trusted - owner-scoped path, encoding, size, sha256 and byte count, schema version, workout id, sample count, per-sample plausibility, and series bounds against the reference.
  The schema version is the one exact match in that list: `WorkoutHeartRateSidecarValidator` requires the blob to carry `WorkoutHeartRateStorageBlob.currentSchemaVersion`, so bumping that constant strands every already-uploaded sidecar as `.malformed` unless the validator is taught to read the older shape at the same time.
  Every failure resolves to one case of `WorkoutHeartRateSidecarError` - missing, forbidden, and integrity/schema faults are distinct from transient ones - and is recorded as a privacy-safe diagnostic carrying the error class, not sample values.
  Only transient failures retry automatically, riding the app-wide connectivity lifecycle rather than a private retry loop; anything else waits for the explicit retry affordance on the workout.
- Hydration is idempotent and runs more than once per process. Only the first pass merges remote documents into existing local workouts - later passes retry sidecars and never re-apply a remote document over a local edit.
  A workout already queued for remote deletion is never re-inserted from its surviving remote copy.
- Schema-one references uploaded before integrity metadata existed carry none of it, so those fields stay optional on the reference and in `firestore.rules`. Absent means "unverifiable, still restorable", never "invalid" - restoring an older backup must keep working.

### Boundaries
- Private workout backups are *private*. Future public sharing, posts, comments, or likes must use *separate public data models* - they don't read private workout documents directly. The privacy boundary is data-model separation, not just security rules.
- Multi-account-on-same-device is not yet supported. Local workout history assumes one user per install; shared local history across accounts is out of scope until intentionally designed.

## Workout Measurement

Workouts are described by **absolute, measured signals** - steps, duration, cadence (steps per minute), and optional supporting data (heart rate, calories, RPE, added weight). There is no user-calibrated effort score, no base level, no relative-to-fitness intensity calculation. We trust what was measured.

**Why no base level:** the personalization it enables - adjusting workout effort relative to a personal baseline - isn't load-bearing. Live Climbs are target-step-count challenges (same target for everyone). Routines expose their own absolute difficulty (level + duration sequences) for self-selection. Leaderboards rank by absolute metrics. Best Efforts compares the user to their own past. None of these need a fitness baseline, and asking for one at onboarding adds friction before the user has felt any value.

**What stays:**
- The canonical mapping between StairMaster levels (1-25) and steps-per-minute is preserved as a **display utility**. Surfaces that want to show "you stepped at the equivalent of level 8" alongside a workout's cadence read from this shared mapping - don't duplicate the math.
- Historical percentile remains as a ranking layer over absolute metrics, computed against the user's own workout history ("harder than 85% of your past sessions"). It's a personal benchmark, not a calibrated effort definition.
- Every workout mutation (create, edit, delete, import) still triggers a recompute of derived data - Best Effort inputs, percentile snapshots, local leaderboard aggregates. Surfaces reading derived values trust them to be current.

**What's deprecated (don't extend):** base level state (seed value, auto-calculated estimate, manual override); "fitness level" terminology and migration code; user-calibrated effort score; base-level seeding UI in onboarding; manual base level override in settings.

Existing code for these can stay until the cleanup task lands, but treat it as legacy - don't add features through it, don't introduce new dependencies on it, and prefer absolute metrics in new code.

## Reference
- Changing what `Workout` persists - adding, removing, renaming or retyping a stored property - is a schema migration; see `ascend-data-migration` before editing the `@Model`.
- `docs/heart-rate-zones-plan.md` - heart rate zones (marked POST-LAUNCH parked).
