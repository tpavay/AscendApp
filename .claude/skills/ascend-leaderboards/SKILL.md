---
name: ascend-leaderboards
description: Use when working on Ascend leaderboards - the global leaderboard tab, per-climb leaderboards, ranking, podium, rank subtitles, tie handling, achievement tiers (Top 1/3/10/100), week boundaries, leaderboard periods/windowing, or leaderboard publication and sync. Covers the Monday-week rule, the current-period-only document model, and standard competition ranking.
paths:
  - AscendApp/Features/Leaderboards/**
---

# Leaderboards

Two distinct surfaces - the global tab (community-wide aggregate stats) and per-climb leaderboards (completion times for one specific climb). They share data-model conventions but use different layouts and emphasis.

## Week Start + Leaderboard Windowing

### Week boundaries
- Monday is the single app-wide week start. Don't reintroduce a user-configurable week-start preference or selection UI.
- Home summaries use Monday-based weeks in the user's local timezone.
- Competitive / global leaderboards use canonical Monday-based weeks in UTC.
- Per-week user-configurable numeric targets are intentionally out of scope. Don't reintroduce target cards, setup prompts, or CRUD around personal weekly goals unless product explicitly changes direction.

### Document model
- Leaderboard documents are **current-period-only**, not historical archives. One document per user per time frame: weekly, monthly, yearly, all-time.
- Each document carries metadata (schema version, time frame, period key, period start timestamp) and the aggregated metrics for the period (steps, floors, workouts, duration, pace). The exact field names live in `firestore.rules`; the Firestore schema-change rule (see `ascend-firebase-data`) governs how to extend or modify them.

### Metrics
- **Steps** is the canonical climb leaderboard metric.
- **Floors** is supporting / display data only and must never change rank order.
- **Pace** leaderboards rank by canonical steps-per-minute (SPM), not by viewer-preference floors-per-minute.

### Publication & sync
- Leaderboard publication is mutation-driven: workout create / import / delete always affects publication; workout edits affect publication only when leaderboard-relevant fields change (date, duration, steps, floors). Photo, notes, heart-rate, calorie, or MET edits don't touch leaderboard publication.
- The leaderboard refresh UI must never own the only publication path. Users must appear remotely even if they never open the leaderboard tab.
- Local leaderboard state updates incrementally for current periods only. Full-history rebuilds are reserved for migration, repair, or schema backfill.

## Leaderboard UX Flow

### Global leaderboard tab - aggregate stats across the community
- The tab root is a category hub previewing each canonical metric (climb, workouts, duration, pace per the Week Start + Leaderboard Windowing rules). A "see all" affordance opens a per-metric detail screen.
- Per-metric detail screens lock the metric and filter by time frame (weekly, monthly, all-time).
- Detail screens compose from focused, reusable subviews - time-frame picker, podium (top 3), pinned current-user row when not in podium, rank list. Don't reimplement these patterns per metric.
- The podium always renders three slots even when sparse; empty slots use a motivational empty-slot treatment.
- The current user appears in exactly one place at a time. If they're in the podium, they're not duplicated in the rank list below.
- Rank subtitles must be chase-oriented. Show earned percentile bands only at Top 1%, Top 5%, Top 10%, Top 25%, or Top 50%; never render low-value percentiles such as Top 98% or Top 100%. Below Top 50%, show the nearest meaningful steps target instead: Top 100 when unlocked, otherwise Top 10, or Top 50% when that is the relevant next tier.
- Active rank cards use this ladder: #1 `DEFENDING GOLD · X AHEAD`, tied #1 `TIED FOR GOLD`, #2 `X STEPS FROM GOLD`, #3 `X STEPS FROM SILVER`, #4-10 `X STEPS TO BRONZE`, #11-100 after the Top 100 population threshold `TOP 100 · X TO TOP 10`, and #11+ before that threshold `X STEPS TO TOP 10`.

### Per-climb leaderboard - completion times for one climb
- Top finishers (#1, #2, #3) get medal-color emphasis (see the medal tokens in the core guide's Design System). They're the *active* prize being chased.
- The climb's First Ascent holder is surfaced as a quiet, persistent annotation - permanent prestige, but visually secondary to the active leaderboard chase. See the First Ascent principle in `ascend-live-climbs`.
- Achievement terminology is locked to **Top 1**, **Top 3**, **Top 10**, and **Top 100**. Top 1 may be swapped to a product-approved label later, but it must be centralized as a single string constant.
- Achievement counts use cumulative inclusive counting: a Top 1 finish also counts toward Top 3, Top 10, and Top 100. Do not render these as mutually exclusive medal bands.
- Achievement counts are also **time-frame agnostic**: a weekly, monthly, and yearly Top 10 finish all count toward the same Top 10 badge, because the badge shows one total per band with no period noun.
  The time frame is preserved on the individual achievement record (`weekly_top_1`, `monthly_top_1`, …), which is what the achievement history sheet reads.
  The counters live in `profile_stats` as `top_N_finishes` - they were once named `top_N_weeks`, which read like a weekly-only tally and got the frame-agnostic behavior mis-filed as a bug.
  Changing what a badge counts is a product decision, not a bug fix.
- Per-climb leaderboards rank *completed attempts on one climb*, not aggregate community totals. They don't share a layout with the global aggregate leaderboards.
- The static per-climb leaderboard shows **every completed attempt**, not best-per-user. A user appears as many times as they've completed the climb; this surface is the historical record of completions. Contrast with the in-session live race, which ranks against best-per-user (see the replay leaderboard architecture in `ascend-live-climbs`).

### Tie handling (applies to global and per-climb)
- Ties are ranked using **standard competition ranking** ("1, 2, 2, 4"). Tied users share the same rank; the next rank is skipped by the count of tied users. This matches the sports convention and honors the honest outcome.
- `CompetitionRanking` (`AscendApp/Shared/Models/`) is the only client-side definition of rank, and it mirrors the Cloud Functions ranking. Rank every client surface through it rather than by list position - a positional rank silently disagrees with the rank the server used to award achievements. A sort tiebreak (uid, document ID) exists to make ordering stable and must never influence rank.
- Don't break ties with secondary metrics (steps tie != floors tiebreaker; time tie != cadence tiebreaker). Adding a secondary criterion quietly changes what the leaderboard measures.
- Don't break ties with submission timestamp. First-to-submit is a property of when the user happened to climb, not how well they climbed.
- Match precision to perception. Per-climb completion times rank at second granularity; sub-second tiebreakers feel arbitrary and don't reflect anything users perceived during the attempt.
- Tied ranks must be visually obvious in the UI - same rank number on each tied row, "T" prefix or equivalent treatment. Don't render ties as if they were ordered.
- Podium display must handle tied top ranks (e.g. three users tied for #1) by giving each climber their own pedestal, filled in leaderboard order. A pedestal's position drives geometry only; the climber standing on it carries their own rank, so two climbers tied for gold both read "T1" in gold even though only one pedestal stands centre. `LeaderboardPodiumLayout` owns the slot assignment and the podium/list split - never key pedestals by rank or partition on `rank <= 3`, because repeated ranks silently drop climbers off both surfaces. The podium is a *visual* surface; the ranking rule is the source of truth.
- First Ascent is exempt - it's keyed on submission timestamp and is unambiguous by design. Two users may tie on the leaderboard, but only one submission reached the backend first.
