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
- A routine is an ordered sequence of **intervals**, each specifying a target level (1-25 on the StairMaster mapping) and a duration. The session ends when all intervals are completed, or when the user ends early.
- Routines are content-driven: server-published catalog entries plus user-created routines. Adding a new routine should never require an app release. The same content-driven principle that applies to the climbs catalog applies to routines.
- User-created routines live alongside server-published routines and use the same model. The browse surface distinguishes them visually (e.g. "My Routines" vs. catalog) but the detail / live / leaderboard experiences are the same.

## Per-routine leaderboards
- Every routine has its own leaderboard. Completing a routine publishes the user's attempt onto that routine's leaderboard.
- Leaderboards include a **"Just Me" toggle** so the user can switch between the global ranking and their own attempt history filtered to that routine.
- Leaderboard rankings use absolute metrics (matching the "no calibrated effort score" rule in `ascend-workout-model`). The ranking metric for a given routine is whichever absolute signal best reflects performance on that routine's intervals - typically a combination of completion, total session duration vs. target, and adherence to interval levels. Don't introduce a calibrated effort score for routine ranking.

## Live routine sessions
- Routine completions come only from the live routine flow (analogous to how Live Climb completions come only from the live climb flow). Manual entries and external imports cannot complete a routine. The canonical statement of this integrity gate lives in `ascend-workout-model`.
- The live experience is routine-specific: current interval, target level, time remaining in interval, progress through the full routine, real-time step count. It is NOT the same UI as a Live Climb (which is structured around a step-target race), even though both share the headphone-motion sensor pipeline.

## Routines vs. challenge climbs
- The "challenge climb" concept stays alive but as a **subtype of climbs**, not a way to absorb routines. A challenge climb is a regular climb (target step count tied to a landmark) with additional constraints layered on - e.g. "you must sustain level 12+ for the final 5,000 steps." Challenges live inside the climbs feature; they do not replace or absorb routines.
- The two features answer fundamentally different user intents: routines = open-ended interval training, climbs = destination-focused races. Don't conflate them.

## Visual identity
- Each routine's interval sequence has an intrinsic **shape** (a pyramid, a plateau, alternating spikes, etc.) that visually encodes what the workout feels like. Treat that shape as the routine's primary visual identity - a hero-sized stylized rendering of the interval bars on the detail screen, not a generic data viz widget tucked in a corner.
- Don't require per-routine illustrations or category icons. The interval shape itself differentiates one routine from another and works automatically for user-created routines without needing a designer in the loop.
- Reuse the shared `SegmentedHeatmapSlider` for 1-25 level selection in the interval builder - see `ascend-design-system`.
