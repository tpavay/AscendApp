---
name: ascend-brand-voice
description: Use when writing or reviewing any user-facing Ascend copy - headlines, CTAs, empty states, microcopy, onboarding text, paywall copy, notifications, or App Store text. Also use when deciding whether a proposed feature fits Ascend's niche. Covers the niche-aggressive declarative voice, the state-then-action empty-state pattern, and the scope guard for what Ascend is not.
---

# Brand Voice

Voice is niche-aggressive and declarative - confident about who Ascend is for, willing to lose readers who aren't the target. The user already chose to be here; the copy doesn't beg.

Consult the `product-design-playbook` skill's relevant plays before shipping design or copy changes.

## Principles
- **Active verbs at the front.** *Climb. Race. Rank. Push.* Avoid "explore" / "discover" / "learn" as openers - too passive. "Track" is not one of them: it is the tracker positioning the product was moved off.
- **Imperative over invitational.** *Be the first* beats *You could be the first*. *Climb past them* beats *You may want to try*.
- **No hedging.** Cut "maybe," "perhaps," "if you'd like," "feel free to."
- **Specific over abstract.** Name landmarks, name verbs, name numbers when they're earned. Concrete words land harder than generic ones.
- **Assume the user is serious.** Don't explain stair stepping. Don't soften "race." Don't add tutorial scaffolding to copy that should land in one read.
- **The dare beats the invite.** Empty states, first-action prompts, and first-time experiences should *dare* the user, not coax them.

## Empty states: state-then-action

State the current condition, then issue an imperative call to action. Two short sentences. The state contextualizes the action; the action drives behavior. Don't ship empty states that are descriptive-only - every empty state is an activation moment. When designing or writing an empty state, consult the `product-design-playbook` skill's Empty States play for the underlying framework.

## Scope guard - what Ascend is NOT

Defining the niche by exclusion. Use this as a check when adding features, screens, or copy:

- **Not for users who don't care about the stair stepper.** If a feature serves "any fitness user," it probably doesn't belong here.
- **Not a social fitness network.** No social feed, no follower model, no kudos. Interaction with other users happens *on the climb* (leaderboards, racing against past attempts), not on a social timeline.
- **Not a generic fitness tracker.** Don't drift toward "every workout, any activity." Activity scope is stair stepper sessions.
- **Not weight-lifting / strength-training focused.** Weighted-vest tracking exists to honor stair-stepper users who add load, not to become a strength app.
- **Not a passive tracker.** Every session is competitive context - pushing for PRs, climbing leaderboards, chasing First Ascents.
- **Not a logger or an importer.** Every climb and record comes from a session performed in Ascend; manual entry and Apple Health workout import are being removed (#437). Apple Health stays only to enrich an Ascend-owned climb; what Ascend reads versus what it attaches are two different sets, stated once in `CLAUDE.md` under "What Ascend Is NOT" - quote those sets from there rather than paraphrasing them, because the legal pages have to match. No copy - in-app, website, legal, listing, or email - may promise logging, importing, or generic workout tracking. Outward copy derived from this positioning: `docs/app-store-racing-repositioning-proposal.md`.

## Locked copy
- Unclaimed climb / no finisher: "First Ascent open. The first finisher claims it forever." Use verbatim (see `ascend-live-climbs`).
- Achievement terminology is locked to Top 1, Top 3, Top 10, Top 100 (see `ascend-leaderboards`).
- Cloud sync is described as **sync**, never "backup" or "upload", in every user-facing string: `Syncing` while it is quietly working, `Couldn't sync this climb` with a `TRY AGAIN` control when the climber has to know, `Synced` transiently once it lands, and `OFFLINE` / `SYNCING` on the control itself. The warning text does not change while a retry is running - it is a statement about whether the climb is safe, and a retry in flight has not made it safer. Owner: `WorkoutSyncStatusRow`; the states behind it are `ascend-workout-model`.
