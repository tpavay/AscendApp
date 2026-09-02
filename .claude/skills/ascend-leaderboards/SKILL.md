---
name: ascend-leaderboards
description: Use before touching ANY ranked surface - a live race board, a completion summary, a share card that carries a rank, Climb Detail's ALL TIMES board, the global leaderboard tab, a rank sentence, a field-size line, or any Cloud Function that derives or freezes a standing. Owns the one statement of what a rank means and which population each surface counts, plus the Monday-week rule, the server-derived document model and its plausibility envelope, tie handling, achievement tiers (Top 1/3/10/100), and how a standing is derived, retained, and backfilled.
---

# Leaderboards

Two distinct surfaces - the global tab (community-wide aggregate stats) and per-climb leaderboards (completion times for one specific climb). They share data-model conventions but use different layouts and emphasis.

## The rank model

This is what a rank means on every Ascend surface.
It is stated once, here.
`ascend-live-climbs` and `ascend-share-composer` point at this section; nothing restates it.

Ascend counts different populations on different screens on purpose, and that is correct rather than a smell - a board that lists every time and a rank that counts people are answering two different questions.
What breaks is a screen that counts one population and names another.
The failures all land on the seam between two surfaces rather than inside one, so the seams are stated directly at the end instead of being left to infer from two rules sitting apart.

### 1. During a climb

The board shows **one row per unique climber, at that climber's best time**.
Never one row per attempt.
You are one of those climbers, and your row is ranked like anyone else's.

**Your row shows your current run** - the live time and the current steps of the climb happening right now.

**Your previous best is not a row.**
It is the `BEST` marker drawn inside your own row's progress fill, at the position that best reached.
It takes no rank cell, it is never tappable, and it is **never counted in the rank or in the field size**.
You are counted once, as yourself.

The marker's source is your **best** previous climb across all previous attempts, never your most recent.
What you are chasing is your best, which is why the word on it is `BEST`.

### 2. The summary right after you finish

It shows **where you stood at that moment**.
Five of six means five of six, then.

That standing is computed on **that climb's own time**, never on your all-time best.
You finished in 9:40, so the summary ranks a 9:40 against the other climbers at their bests.
Your 8:12 has its own summary, showing 8:12 and the rank an 8:12 earned when it landed.

### 3. That same summary, reopened later

It **still says five of six**, because that is what you were at that time.
It never re-computes.
The share card for that climb carries the same time and the same number.

### 4. Climb detail

**This is where everything lives: all of your attempts and everybody else's.**
Every completed attempt is its own row, so one climber can hold three rows and the whole podium.
That board is titled `ALL TIMES`, not `LEADERBOARD`.

### 5. Every surface names the population it counted

So the words match the number.
A figure counted over climbers says `CLIMBERS`; a figure counted over completed attempts says `COMPLETIONS`.
The noun comes from what was counted, never from what the screen happens to be about.
A surface holding a count it cannot characterise states no field size at all.

### The seams

**Your row versus your marker.**
Both are you.
The row is ranked and counted; the marker is neither.
If a field size moves when your own previous best appears, it counted you twice.

**A rank sentence versus the rows a board draws.**
These are different questions, and the answers are allowed to differ on one screen.
An open Just Climb has no target and a plain routine ranks on steps, so both draw every completed attempt as its own row and race it as its own opponent.
The rank sentence beside those rows still counts **unique climbers on both halves**: a tower with 41 finishes from 16 climbers, where 5 distinct climbers beat you, reads `6TH OF 16`.
Never `13TH OF 16`, and never `13TH OF 41`.

**The live number versus the frozen number.**
A rank recomputed from today's rows is a *current* standing; the rank stamped when your attempt published is what you *were*.
They are supposed to differ, and each says which it is.
They never mix: a frozen position over a live denominator is a number that was never true, so a rank and its denominator always resolve together from one source.

**The summary versus climb detail.**
A summary counts climbers; climb detail lists every time.
The same tower shows two different totals and both are right, because each one names what it counted.

**Solo versus a real field.**
When a real field of climbers exists, the leaderboard rank is the hero.
When you are the only finisher on the tower there is no leaderboard rank at all - the hero states your placing among your own climbs, an ordinal over `OF YOUR N CLIMBS`.
When both are true, the leaderboard rank leads and the personal placing drops to the achievement row.
`1ST OF 1 CLIMBER` never appears: a number you cannot lose is not a result, and being alone on a climb already has a permanent name, which is First Ascent.

### Anchors

Each statement has a test behind it. `scripts/test/rank-model-contract.test.mjs` keeps this section single-homed and checks that each anchor below still exists, so deleting one fails rather than ships.

1. During a climb - `AscendAppTests/LiveReplayFieldPopulationTests.onlyPerClimbAndPerTemplateContextsCollapseRepeats`. The `BEST` marker has no anchor yet because it has no code yet; it is being built on issue #561.
2. The summary right after you finish - `functions/test/liveReplayLeaderboard.test.ts`, "counts a repeat rival once on a board that races climbers" and "never seats a climber behind their own earlier best".
3. Reopened later - `AscendAppTests/CompletedClimbRankFreezeTests.aLaterServerReadNeverMovesAnAlreadyFrozenRank`, and on the share card `AscendAppTests/SavedClimbShareRankTests.aStoredFrozenStandingReachesTheSavedClimbShareCardWithoutARequest`.
4. Climb detail - `AscendAppTests/ClimbLeaderboardPageContentTests.presentRowsResolveToRows`, plus the `ALL TIMES` title, which the contract test reads out of `ClimbDetailView`.
5. Naming the population - `AscendAppTests/LiveReplayFieldPopulationTests.fieldSizeLabelNamesThePopulationAndGroupsTheNumber`.

## Week Start + Leaderboard Windowing

### Week boundaries
- Monday is the single app-wide week start. Don't reintroduce a user-configurable week-start preference or selection UI.
- Home summaries use Monday-based weeks in the user's local timezone.
- Competitive / global leaderboards use canonical Monday-based weeks in UTC.
- **A week is not contained by a month.** The weekly window straddles the month boundary for up to six days a month, so a populated weekly board beside an empty monthly board is arithmetic, not data loss - on 2026-08-01 the weekly window had been open since Jul 27 while the monthly window was hours old.
  Do not "fix" that by nesting the windows; it would change what the weekly board measures.
  Every board names its own window (`LeaderboardPeriod.windowLabel` / `.windowSubject`) precisely so the pair cannot read as a contradiction.
- Period keys are derived independently in three places that must agree exactly: `LeaderboardTimeFrame.currentPeriod` (client), `functions/src/leaderboardPeriod.ts` (the one Cloud Functions derivation - both the finalizer's `previousPeriod` and the standings derivation's `currentPeriod` live there), and `currentPeriod` in `scripts/lib/leaderboard-period.mjs` (the one seeding derivation - `seed-demo-user.mjs` and `seed/fixtures/profile-fixtures.mjs` both import it; don't author a fourth copy).
  Week 1 is the week containing Jan 1, so a week key can carry the *next* calendar year (`2025-12-29` is `2026-W01`). All three read `SharedTestVectors/leaderboard-period-key-vector.json` - `LeaderboardTimeFrameTests.periodKeysMatchTheServerAndSeedDerivation`, `functions/test/leaderboardAchievements.test.ts` and `functions/test/leaderboardStats.test.ts`, and `scripts/test/leaderboard-period.test.mjs`. Add a case there rather than editing one derivation in isolation: a document written under one spelling is invisible to a reader using another, and the board just looks empty.
- Per-week user-configurable numeric targets are intentionally out of scope. Don't reintroduce target cards, setup prompts, or CRUD around personal weekly goals unless product explicitly changes direction.

### Document model
- One document per user, per time frame (daily, weekly, monthly, yearly, all-time), per period, and the client only ever reads the **current** period. A closed row is never an archive to read from; whether it is kept or pruned is the retention rule under Publication & sync, and the reason is always what still reads it.
- Each document carries metadata (schema version, time frame, period key, period start timestamp) and the aggregated metrics for the period (steps, floors, workouts, duration, pace). The exact field names live in `firestore.rules`; the Firestore schema-change rule (see `ascend-firebase-data`) governs how to extend or modify them.

### Metrics
- **Steps** is the canonical climb leaderboard metric.
- **Floors** is supporting / display data only and must never change rank order.
- **Pace** leaderboards rank by canonical steps-per-minute (SPM), not by viewer-preference floors-per-minute.

### Publication & sync
- **The client never writes a standing.** `leaderboard_stats` is `allow write: if false` in `firestore.rules`, and `functions/src/leaderboardStats.ts` is the single site that derives a row - from the canonical `users/{uid}/workouts` documents, through the Admin SDK. The device writing its own totals is issue #307: rules validated the document's shape and its identity but never its evidence, so one HTTPS request bought first place on every board and a permanent achievement to go with it. Never reintroduce a client write, and never add a "just this one field" exception - a partial write is still a client-authored number in an award-minting document every paying climber reads.
- **What triggers a rederivation is the workout backup, not a publish call.** A standing appears because `users/{uid}/workouts` changed; demographics refresh because `users/{uid}` changed. There is no publish path to gate, retry, or debounce, and no leaderboard-specific kill switch: the choke point is `workout_cloud_backup_writes_enabled`, which defers the evidence and therefore the standing.
  Both triggers gate on the fields they actually read - `leaderboardEvidenceChanged` over `startedAt` / `durationSeconds` / `steps` / `floors` / `source`, and `demographicsChanged` over the five filter fields. A photo finishing its upload, a note, a heart-rate sidecar reference or a calorie edit changes no total and must not rederive anything.
- **Ownership is a parameter, and the triggers pass the conservative one.** `reconcileLeaderboardStats` takes `{ownership}`. Both Cloud Function triggers use `openPeriodsOnly`: they may rewrite or delete only `leaderboardDocumentId(uid, timeFrame, currentPeriod(timeFrame, now).key)`. The reason is that nobody is watching a trigger - `finalizeLeaderboardAchievements` can be running concurrently, and a trigger that touched a closed window would race the job freezing permanent awards from it. Never widen the trigger's ownership.
- **Retention follows what still reads the row, not whether the period closed.** A closed *weekly / monthly / yearly* row is retained for two independent reasons: the finalizer reads the previous period's rows at 00:15 UTC, and the achievement it writes stores `leaderboardStatsId` pointing back at that row as the award's provenance, so removing it later orphans a permanent record. A closed *daily* row is not in `FINALIZED_TIME_FRAMES` and the client only ever queries the current period, so nothing reads it again and it is pruned - left immortal it adds one dead document per active climber per day to an already unpaginated per-user read. `all_time` never closes. The window comes off the row's stored `timeFrame` and `periodStartAt`, never from parsing the document id; a row that cannot say which window it belongs to is left alone.
- **A row is derived, so it can be un-derived.** Delete the workouts and the open-period standings go with them; an open period the climber has no evidence in yields no row rather than a stale one. The one exemption is a seeded competitor (`isSynthetic: true`), which the derivation neither rewrites nor removes - the same exemption identity propagation already makes.
- **The server holds no evidence a determined client could not manufacture.** Every workout document is still device-authored: there is no App Check attestation and no server-side sensor ingestion. What bounds forgery today is two envelopes at two different moments, and they are deliberately not the same numbers. At *write* time `isPhysicallyPossibleClimb` in `firestore.rules` refuses only what no human could have done, because a refused write is a climb that can never back up - `ascend-firebase-data` owns those bounds and the reasoning. At *derivation* time this function filters what merely should not score: 220 steps per minute (mirroring `WorkoutPlausibilityPolicy`), no session longer than a day, and no period whose sessions total more wall clock than the period's full length. Together they turn an unbounded forgery into a human-scale one; they do not eliminate it. Closing the rest means building the evidence path, and any claim that standings are "verified" is wrong until that lands.
- **State the derivation envelope's limit precisely: it does not cover all-time.** The wall-clock bound is real for daily, weekly, monthly and yearly, whose windows are fixed calendar spans the client cannot move. All-time has no start, so its budget is anchored at the climber's own earliest workout - and that workout is client-authored, so one backdated session moves the anchor and buys years of headroom. Anchoring at account creation would add precision the evidence does not support. The exposure is a visible all-time ranking, not a frozen award: the finalizer mints permanent achievements from weekly, monthly and yearly only (`FINALIZED_TIME_FRAMES`), never from all-time. Do not describe the envelope as bounding every board.
- **Where bounding an abuser and protecting a real climber pull apart, protect the climber.** The budget is the period's full length rather than the elapsed part of it, precisely because the elapsed form dropped an honest climber's whole daily row when two connected sources recorded the same early-morning climb. A slightly loose bound beats one that erases a real standing.
- **Which origins count is one constant, and it may never exceed what the rules admit.** `COMPETITION_ELIGIBLE_SOURCES` in `functions/src/leaderboardStats.ts` currently matches `isValidWorkoutSource` in `firestore.rules`, which is what the device counted before the derivation existed. A test reads the rules text and asserts the set is a *subset* of it: a name here the rules refuse is dead text stating a second, looser policy nothing can exercise - `garmin` and `fitbit` were exactly that, and are now gone from both. Subset rather than equality on purpose, so the captain's competitive-eligibility decision of 2026-07-27 - only Ascend-controlled live sensor sessions count - can narrow this constant and its test without fighting the pin. That narrowing is a product change with visible blast radius, not a bug fix.
- Local leaderboard state (`LeaderboardStats` in SwiftData) is a **display-only optimistic cache**, never the authority. `LeaderboardCurrentUserReconciler` overlays it onto the fetched board so a climber sees their own session immediately; it can say "your numbers are here", never "you rank here". It updates incrementally for current periods only, and full-history rebuilds stay reserved for migration, repair, or schema backfill.
- `scripts/backfill-leaderboard-stats.mjs` reconciles an environment against this derivation, importing the compiled function rather than reimplementing it. Run `--dry-run` first: a row whose published total exceeded its workouts is either forged or a defect in what the device counted, and both deserve reading before they are overwritten.
  It passes `openPeriodsOnly` by default, matching the triggers. `--include-closed-periods` switches it to `openAndStoredPeriods`, which additionally owns every window a stored row names - the only way to reach a client-authored row sitting in the window the finalizer is about to freeze awards from. The flag is opt-in on purpose: that reach is a supervised, dry-run-first operation, not something that should ever fire unattended.
  The dry run prints, for every closed **award-bearing** row it would touch (weekly, monthly, yearly - a daily row can never carry an award), the window's real start and end dates, stored vs derived totals with the delta, and how many eligible workouts the derived value was built from - zero workouts behind a large stored total is the signature of forgery; a small delta with real evidence behind it is drift. It also reads `leaderboard_periods/{timeFrame}_{periodKey}` and reports each period's status, because **repairing a row does not unwind an achievement already minted from the old number**. A period reading `finalized` means the award in `users/{uid}/achievements` needs separate attention; do not describe the backfill as having fixed it.
- **The report must never state an evidence finding it did not make.** A window that was derived and came back empty and a window that was never derived produce the same empty result and mean opposite things, so the removal reason travels from the derivation to the report (`LeaderboardRemovalReason`) rather than being inferred. A pruned closed daily row is routine housekeeping and is counted and worded separately; printing "0 eligible workouts" for a window nobody derived would make yesterday's honest row read exactly like a forged one, which is the distinction the dry run exists to draw.
- **Removing a row for an already-finalized period is a second, harsher act.** The achievement survives but its `leaderboardStatsId` provenance is gone, and that is not reversible, so the backfill refuses it unless `--allow-finalized-provenance-loss` is passed on top of `--include-closed-periods`. It is never implied by the broader flag.
  The guard is an **allow-list, not a deny-list**: a removal proceeds only when `leaderboard_periods/{timeFrame}_{periodKey}` is absent, which is the one positive signal the awards job has not run. `finalizing` is refused outright even with the flag - the finalizer holds it for up to `FINALIZING_LOCK_MINUTES` while reading exactly those rows, so deleting mid-read is a race rather than a decision. Any other status, including one a later finalizer adds or a document with no status field, also refuses: an unrecognised status means the tool cannot tell whether an award is being minted, and the safe answer to "I do not know" is no. **Where the two are in tension, refuse** - a removal wrongly refused costs a second run, a removal wrongly allowed destroys a permanent award.
  The status is read through `LeaderboardStatsTransaction.readPeriodFinalization` inside the same transaction that performs the removal, during its read phase (Firestore forbids reads after writes). A pre-run snapshot cannot see a lock taken afterwards; reading it transactionally makes a concurrent finalizer abort and retry the reconciliation so the decision is re-made.
- **Legacy `{uid}_{timeFrame}` rows can never be re-derived** - their identifier encodes no period, so a removal is final. They are not inert: `leaderboardRowsForPeriod` matches on `timeFrame` + `periodStartAt` with no constraint on document id and breaks ties by newest `lastUpdated`, so one can still win a permanent award, and the client write path this change deleted took their only sweeper (`LeaderboardRepository.deleteLegacyStats`) with it. `reconcileLeaderboardStats` reports them in `unresolvableRows` on every run, the backfill lists them in their own section, and only `--include-closed-periods` removes them.
- **Publication eligibility is derived server-side, never asserted by the client.** `functions/src/liveReplayLeaderboard.ts` re-derives every condition from the backed-up workout and ignores the participation's `leaderboardEligible` boolean; `WorkoutParticipation.leaderboardEligible` is a local record of what the device concluded, not an instruction the server obeys. Any new leaderboard gate follows the same rule: check evidence fields, never a client-written verdict.

## Leaderboard UX Flow

### Global leaderboard tab - aggregate stats across the community
- **The tab root is one board, not a category hub.**
  `LeaderboardView` shows a single canonical metric (climb, workouts, duration, pace per the Week Start + Leaderboard Windowing rules) and switches between them through its title menu; there is no "see all" affordance and no per-metric detail route.
  The locked-metric mode that once backed one lost its last caller and was deleted, so a metric-detail route is a product decision to rebuild rather than a parameter to pass.
- The board filters by time frame (weekly, monthly, yearly, all-time) and by the demographic filters (age group, body weight, location).
- The board composes from focused, reusable subviews - time-frame picker, podium (top 3), pinned current-user row when not in podium, rank list. Don't reimplement these patterns per metric.
- The podium always renders three slots even when sparse; empty slots use a motivational empty-slot treatment.
- The current user appears in exactly one place at a time. If they're in the podium, they're not duplicated in the rank list below.
- **A rank is earned by climbing inside the window; it is never conferred by holding an account.** A climber with nothing logged this period is *unranked* - `LeaderboardCurrentUserReconciler` drops them from the ranked entries, and their pinned row renders with no rank number (`LeaderboardUserStanding.unranked`). Never synthesise one from list position: that is what put a "rank 2, 0 steps" row directly beneath a podium whose second plinth read `OPEN`. This is the live recurring board, not a completed climb, so the frozen-rank rule does not apply.
- Rank subtitles must be chase-oriented. Show earned percentile bands only at Top 1%, Top 5%, Top 10%, Top 25%, or Top 50%; never render low-value percentiles such as Top 98% or Top 100%. Below Top 50%, show the nearest meaningful steps target instead: Top 100 when unlocked, otherwise Top 10, or Top 50% when that is the relevant next tier.
- Active rank cards use this ladder: #1 `DEFENDING GOLD · X AHEAD`, tied #1 `TIED FOR GOLD`, #2 `X STEPS FROM GOLD`, #3 `X STEPS FROM SILVER`, #4-10 `X STEPS TO BRONZE`, #11-100 after the Top 100 population threshold `TOP 100 · X TO TOP 10`, and #11+ before that threshold `X STEPS TO TOP 10`.

### Per-climb leaderboard - completion times for one climb
- Top finishers (#1, #2, #3) get medal-color emphasis (see the medal tokens in the core guide's Design System). They're the *active* prize being chased.
- The climb's First Ascent holder is surfaced as a quiet, persistent annotation - permanent prestige, but visually secondary to the active leaderboard chase. See the First Ascent principle in `ascend-live-climbs`.
- Achievement terminology is locked to **Top 1**, **Top 3**, **Top 10**, and **Top 100**. Top 1 may be swapped to a product-approved label later, but it must be centralized as a single string constant.
  That is the awarding taxonomy, not the badge set: which badges a profile shelf renders from it - and why the Top 3 band badge gave way to the exact `#2` and `#3` placements read off each record's rank - belongs to `ascend-profile`.
- Achievement counts use cumulative inclusive counting: a Top 1 finish also counts toward Top 3, Top 10, and Top 100. Do not render these as mutually exclusive medal bands.
- Achievement counts are also **time-frame agnostic**: a weekly, monthly, and yearly Top 10 finish all count toward the same Top 10 badge, because the badge shows one total per band with no period noun.
  The time frame is preserved on the individual achievement record (`weekly_top_1`, `monthly_top_1`, …), which is what the achievement history sheet reads.
  The counters live in `profile_stats` as `top_N_finishes` - they were once named `top_N_weeks`, which read like a weekly-only tally and got the frame-agnostic behavior mis-filed as a bug.
  Changing what a badge counts is a product decision, not a bug fix.
- Per-climb leaderboards rank *completed attempts on one climb*, not aggregate community totals. They don't share a layout with the global aggregate leaderboards.
- What that board shows and what it is called are statements 4 and 5 of The rank model above: every completed attempt as its own row, titled `ALL TIMES`, with the shared field-size line (`60 COMPLETIONS`) pinned beneath the rows. The mechanics of that line - which surfaces may state a field at all, and where the noun comes from - live with the replay leaderboard architecture in `ascend-live-climbs`.
- **The board states a climber's own time and rank once - on their own row, wearing the YOU pill - and carries no separate personal rank summary above it.**
  History is the home for a climber's own results, and the hero card's finisher strip already carries the standing.
  The accepted cost is that a climber ranked past the 25-row page must scroll to find themselves; reintroducing a pinned current-user row is a product decision, not a fix.
  `ClimbDetailViewModel.hasPersonalCompletionStanding` is not leftover gating from that card: rank and rows arrive from two separate fetches, and it is the only thing stopping a climber who has just finished from being told nobody has (`ClimbLeaderboardPageContent`).

### Tie handling (applies to global and per-climb)
- Ties are ranked using **standard competition ranking** ("1, 2, 2, 4"). Tied users share the same rank; the next rank is skipped by the count of tied users. This matches the sports convention and honors the honest outcome.
- `CompetitionRanking` (`AscendApp/Shared/Models/`) is the only client-side definition of rank, and it mirrors the Cloud Functions ranking. Rank every client surface through it rather than by list position - a positional rank silently disagrees with the rank the server used to award achievements. A sort tiebreak (uid, document ID) exists to make ordering stable and must never influence rank.
- Don't break ties with secondary metrics (steps tie != floors tiebreaker; time tie != cadence tiebreaker). Adding a secondary criterion quietly changes what the leaderboard measures.
- Don't break ties with submission timestamp. First-to-submit is a property of when the user happened to climb, not how well they climbed.
- Match precision to perception. Per-climb completion times rank at second granularity; sub-second tiebreakers feel arbitrary and don't reflect anything users perceived during the attempt.
- Tied ranks must be visually obvious in the UI - same rank number on each tied row, "T" prefix or equivalent treatment. Don't render ties as if they were ordered.
- Podium display must handle tied top ranks (e.g. three users tied for #1) by giving each climber their own pedestal, filled in leaderboard order. A pedestal's position drives geometry only; the climber standing on it carries their own rank, so two climbers tied for gold both read "T1" in gold even though only one pedestal stands centre. `LeaderboardPodiumLayout` owns the slot assignment and the podium/list split - never key pedestals by rank or partition on `rank <= 3`, because repeated ranks silently drop climbers off both surfaces. The podium is a *visual* surface; the ranking rule is the source of truth.
- First Ascent is exempt - it's keyed on submission timestamp and is unambiguous by design. Two users may tie on the leaderboard, but only one submission reached the backend first.
