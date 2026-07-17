---
name: ascend-workout-model
description: Use when working on the canonical Ascend Workout model - workout durability and cloud backup, sync state and the sync coordinator, workout source vs participation separation, sensor capture, plausibility validation, workout measurement (steps, duration, SPM, StairMaster level mapping, historical percentile), or the deprecated base-level/effort-score legacy. Covers the local-first SwiftData + Firestore contract and the workout schema open/closed rule.
paths:
  - AscendApp/Shared/Models/Workout*
  - AscendApp/Shared/Services/Workout*
  - AscendApp/Features/Workouts/**
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

### Integrity rules
- Sensor capture (headphone motion, future wearables) lives behind a shared service layer. The step / progress algorithm is pure compute - unit-testable without hardware. Sensor callbacks must run safely off the main thread; UI updates marshal back to main explicitly.
- Plausibility validation runs at the entry boundary - bad data (implausible step rates, impossible durations) never enters the canonical store. The gate is the same for manual save, edit, external import, and Live Climb completion.

## Workout Durability Architecture

Local-first with cloud backup. SwiftData is the editing surface and source of truth for in-flight UX; Firestore + Storage carry durable backups so a user's history survives reinstalls and crosses devices.

### Identity and storage
- Each workout has *one* durable identity - a stable UUID shared across the local `Workout`, its Firestore document at `users/{uid}/workouts/{workoutId}`, its heart-rate sidecar in Storage, and any associated media. One identity = cleanup and repair flows can act on all resources at once.
- Firestore stores the workout's metadata and summary fields (averages, max HR, totals). Large time-series data (heart-rate samples) goes to Storage as a compressed sidecar - never embedded in Firestore documents. Firestore holds only pointers and summaries.
- A workout is *fully synced* only when every component (Firestore document + Storage sidecar + media uploads) has succeeded. Partial success is not success.

### Sync state
- Per-workout sync state (owner, last-modified, last-synced, status, last error) lives *on the local `Workout` itself*, not in a separate sync queue. This preserves the local-first UX while keeping pending remote work tracked.
- Pending remote deletes are tracked on a separate model so the canonical workout record isn't burdened with retry / deletion state.

### Orchestration
- A single sync coordinator owns all pending remote work. Mutations don't write to Firestore directly - they update local sync state and kick the coordinator.
- Backup is mutation-driven (immediate after each mutation), not deferred to next launch. The coordinator also runs on authenticated bootstrap and foreground repair to recover missed or failed work.
- Ordering: deletes before upserts; Storage sidecars before the Firestore document that references them; overlapping requests coalesced so launch / auth / lifecycle hooks don't produce duplicate remote work.
- Media uploads are part of the durability contract. When media changes after upload completion, the workout is re-marked pending and the backup is republished.

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
- `docs/heart-rate-zones-plan.md` - heart rate zones (marked POST-LAUNCH parked).
