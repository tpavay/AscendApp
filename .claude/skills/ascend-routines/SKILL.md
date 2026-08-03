---
name: ascend-routines
description: Use when working on Ascend Routines - routine structure and intervals, user-created vs catalog routines, per-routine leaderboards and the Just Me toggle, live routine sessions, the interval-shape visual identity, or the routines-vs-climbs / challenge-climb boundary. Covers why routines are a peer feature to climbs, not a subtype.
paths:
  - AscendApp/Features/Routines/**
---

# Routines

Routines are a **first-class peer feature** to climbs - not a stepping stone toward absorption. Climbs and routines coexist as the two canonical live-tracked experiences, and they answer different user intents.

## Climbs vs. routines - the core distinction
- **Climb** = race to a specific step target tied to a real-world landmark ("I'm climbing to the top of the Burj Khalifa"). Fixed destination, fixed step goal, prestige tied to the place.
- **Routine** = open-ended guided interval session ("I'm running through these intervals"). Variable step count depending on how many intervals the user completes. Prestige tied to the routine itself, not a destination.

Both have their own browse, detail, live, and leaderboard surfaces. Don't fold one into the other.

## Routine structure
- `Routine` and `RoutineFolder` are `@Model` types: changing what they persist is a schema migration, not a local edit - see `ascend-data-migration`.
- **A routine the climber authored is backed up; a catalog template never is.** User routines and folders live at `users/{uid}/routines` and `users/{uid}/routine_folders`, private to their owner, uploaded through `RoutineSyncCoordinator` on every mutation and restored by `RoutineHydrationService` on sign-in. `builtin` and `remoteTemplate` routines are server-owned content every device re-derives from `routine_templates`, so uploading one would be writing our own catalog back to us under a climber's uid - `firestore.rules` rejects it and `Routine.isUserAuthored` is the client-side gate. The conflict rule when a local and a cloud copy disagree is stated on `RoutineHydrationService`, and it deliberately matches the workout one.
- A routine is an ordered sequence of **intervals**, each specifying a target level (1-25 on the StairMaster mapping) and a duration. The session ends when all intervals are completed, or when the user ends early.
- Routines are content-driven: server-published catalog entries plus user-created routines. Adding a new routine should never require an app release. The same content-driven principle that applies to the climbs catalog applies to routines.
- User-created routines live alongside server-published routines and use the same model. The browse surface distinguishes them visually (e.g. "My Routines" vs. catalog) but the detail / live / leaderboard experiences are the same.

## Per-routine leaderboards
- Every routine has its own leaderboard. Completing a routine publishes the user's attempt onto that routine's leaderboard.
- Leaderboards include a **"Just Me" toggle** so the user can switch between the global ranking and their own attempt history filtered to that routine.
- Leaderboard rankings use absolute metrics (matching the "no calibrated effort score" rule in `ascend-workout-model`). Don't introduce a calibrated effort score for routine ranking.
- **A routine board ranks on total steps, descending** - the inverse of a climb, which fixes the step target and ranks the fastest clock. A routine's intervals fix the clock instead, so every finisher spends the same time and only the steps taken inside that window separate them; ranking a routine on duration would rank tracking jitter and reward the shortest session. The single source of the mapping is `rankingMetric` in `functions/src/liveReplayLeaderboard.ts`, mirrored by `LiveReplayLeaderboardContextType.rankingMetric` on the client - change both together or a displayed rank will contradict the published one.
- Steps are coarse integers, so ties are common. Equal steps share one competition rank, and the deterministic tiebreak for ordering is the entry document ID (the immutable workout ID), so ranks stay stable across recomputes.
- **Only catalog templates publish.** The board is `routine_template__<templateId>`, so it holds exactly one template and steps stay comparable. A user-created routine is a private UUID nobody else can run; the client already marks those participations `leaderboardEligible: false`.
- **Changing a published template's intervals must ship as a new `templateId`.** Nothing structurally prevents editing intervals in place under a stable ID - the seed script writes with `merge: false`, `version` is hand-maintained, and participation `contextVersion` is hardcoded to 1 - but doing so silently ranks runs of different lengths on one board. Every routine row and rank snapshot stamps `targetDurationSeconds`, so drift is at least visible in the data.

## Live routine sessions
- Routine completions come only from the live routine flow (analogous to how Live Climb completions come only from the live climb flow). Manual entries and external imports cannot complete a routine. The canonical statement of this integrity gate lives in `ascend-workout-model`.
- The live experience is routine-specific: current interval, target level, time remaining in interval, progress through the full routine, real-time step count. It is NOT the same UI as a Live Climb (which is structured around a step-target race), even though both share the headphone-motion sensor pipeline.
- Skipping an interval advances the session but forfeits completion credit for the whole session. Skipping burns the routine clock without taking steps, so a session containing any skip is not a completion: it finishes with the `skipped` stop reason rather than `target_reached`, does not increment the routine's completion count, and carries no leaderboard eligibility on its participation record. It still saves a normal workout with the steps the user actually took. The skip count is checkpointed onto the active draft so resuming an interrupted session cannot launder away earlier skips.
- `target_reached` is the only routine stop reason that earns competitive credit, and `HeadphoneMotionSessionStopReason.earnsCompetitiveCredit` is the only place that decides it - the participation record and the completion summary both read it rather than each re-deriving a verdict that could disagree. Note this inverts the climb reading of `stopReason` (see `ascend-live-climbs`): for a routine the stop reason *does* decide whether it counted.
- Routine sessions publish into the replay index through `parseRoutineReplayPayload` in `functions/src/liveReplayLeaderboard.ts`, gated on `target_reached` plus the client's own `leaderboardEligible` verdict via the shared `hasEligibleParticipation` helper - never a parallel eligibility rule. A routine publishes into exactly one context and never claims a First Ascent, which is landmark prestige and belongs to climbs.

## Routines vs. challenge climbs
- The "challenge climb" concept stays alive but as a **subtype of climbs**, not a way to absorb routines. A challenge climb is a regular climb (target step count tied to a landmark) with additional constraints layered on - e.g. "you must sustain level 12+ for the final 5,000 steps." Challenges live inside the climbs feature; they do not replace or absorb routines.
- The two features answer fundamentally different user intents: routines = open-ended interval training, climbs = destination-focused races. Don't conflate them.

## Visual identity
- Each routine's interval sequence has an intrinsic **shape** (a pyramid, a plateau, alternating spikes, etc.) that visually encodes what the workout feels like. Treat that shape as the routine's primary visual identity - a hero-sized stylized rendering of the interval bars on the detail screen, not a generic data viz widget tucked in a corner.
- Don't require per-routine illustrations or category icons. The interval shape itself differentiates one routine from another and works automatically for user-created routines without needing a designer in the loop.
- **A block's height and colour both come off its level on 25 steps, and `RoutineIntervalScale` is the only place that says so.** Five `IntensityTier` steps used to drive bar height, which drew level 16 and level 20 identically - unreadable once the timeline became the authoring surface. Anything rendering an interval bar reads that type, so the shape a climber drags in the builder is the shape the list card and the thumbnail show.

## Authoring a routine

The builder is a visual timeline editor, not a form: `RoutineEditorView` -> `RoutineTimelineEditor`. There is no interval list and no interval creator, because the timeline block carries the level and the duration itself.

- **Five gestures author an interval, and nothing else does**: tap to select, drag up for the level (1 per step), drag sideways for the time (30 seconds per step), long-press to reorder, and + below the timeline to add. New blocks land Standard at level 1. The step type is the one control under the timeline, beside Delete.
- **Geometry lives in `RoutineTimelineLayout`, not in a view.** Fit to width with a 28pt floor so a short block still holds its number - a render rule only, stored durations stay exact. Horizontal drag is hybrid: the block edge tracks the finger until a 30-second step would cost under 8pt of travel, then it clamps, so one thumb-width never buys minutes on a long routine.
- **Save stays explicit.** `RoutineService.kickBackup()` fires a Firestore upload pass per write, so autosave at drag rate would hammer the backend. Nothing a gesture touches may reach the store on its own.
- **A vertical drag on a block is the level control, so the sheet must not read it as a dismissal.** `RoutinesView` passes `isInteractiveDismissDisabled` for the length of the drag; Cancel in the top left is how you leave.
- **Every block is one accessibility element with an adjustable action for the level**, plus rotor actions for time, step type, move and delete - dragging bars is an invented interaction, so VoiceOver needs an equivalent for each gesture. Strings live in `RoutineIntervalVoiceOver`. Motion respects `accessibilityReduceMotion` through `RoutineTimelineMotion`.
