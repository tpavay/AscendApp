# Ascend — App Brief (handoff-ready)

Last updated: June 10, 2026

A self-contained description of Ascend so a teammate or AI agent can read it cold —
for App Store listing work and for evaluating onboarding screen templates.

**Related docs:**
- [`docs/onboarding-design-guide.md`](onboarding-design-guide.md) — existing template
  analysis (Puff Count chosen as the structural reference) and the onboarding North Star.
  Read this alongside the brief when picking a template.

---

## What it is

Ascend is a **competitive stair-stepper companion for iOS**. It turns every stepping
session into a race up real-world landmarks. Users pick a landmark (Mt. Everest, Empire
State Building, Burj Khalifa), race in real time against other people's past attempts via
headphone-motion step tracking, and either reach the target step count (completion) or
don't (failed attempt). The leaderboard is the conversation.

**The core promise:** Race the world up real landmarks. From your stair stepper.

## Who it's for

People who **already use the stair stepper** (or are about to start) and want their work
to count — goal-driven steppers chasing PRs, leaderboard rank, and progress that compounds
over time. The copy assumes the user is serious and already chose to be here.

## Who it's NOT for (the niche, defined by exclusion)

- Not for general fitness users who don't care about the stair stepper.
- Not a social network — no feed, no followers, no kudos. Interaction happens *on the
  climb* (leaderboards, racing past attempts), not on a timeline.
- Not a generic "any workout" tracker.
- Not a passive tracker — every session is competitive context.

## Hero experience — Live Climbs

Real-time race up a landmark via headphone-motion step tracking. The first person ever to
complete a climb holds its **First Ascent** forever — permanent prestige that can never be
reclaimed, even after faster climbers beat their time. Every new climb drop opens a fresh
First Ascent slot. This is the core retention loop.

## Core features

- **Live Climbs** (the hero) — race to a landmark's step target
- **Leaderboards** — per-climb completion times + global aggregate (steps is canonical)
- **First Ascents** — permanent "world first" prestige per climb
- **Best Efforts** — a personal record book (most steps, longest climb, highest avg SPM…)
- **Routines** — open-ended guided interval sessions (a peer feature to climbs)
- **Workout logging** + Apple Health import (the app also serves as a logger)
- **Share composer** — Instagram-Story-style canvas: pick a background, drag stat
  "stickers" onto it

## Monetization (relevant to onboarding)

**Hard paywall, no freemium tier.**
Two paths unlock the same access: **$49.99/year** with a seven-day free trial, or **$9.99/month** charged immediately with no trial.
There is no weekly product.
Onboarding is a **conversion funnel that ends at a hard paywall**, not a tutorial.

## Brand voice

Niche-aggressive, declarative, confident — willing to lose readers who aren't the target.
Active verbs at the front: **Climb. Race. Rank. Push. Track.** Imperative over invitational
("Be the first" > "You could be the first"). No hedging. The dare beats the invite. Don't
explain stair stepping; don't soften "race."

## Visual identity (the north star for templates)

- **Dark-first and cinematic.** Full-bleed landmark photography, readability overlays, bold.
- **Accent color:** electric lime `#86D30A` — used with discipline, not as a wash.
- **Medal tokens:** Gold `#D4AF37` / Silver `#C0C0C0` / Bronze `#CD7F32`, reserved for
  podium and prestige moments only.
- **Type:** Montserrat (Bold / SemiBold / Medium / Regular).
- **Mark:** an angular "A" that doubles as the letter A in the "Ascend" wordmark — never a
  logo-next-to-text combo.
- **Motifs:** laurels = personal achievement; crowns = competitive dominance (never
  combined).

## Onboarding — current plan + hard constraints (for template evaluation)

Planned sequence:
**1) Welcome → 2) Pre-auth value carousel → 3) Sign-in (Apple/Google) → 4) Survey →
5) Paywall priming → 6) Hard paywall → 7) Home.**

Visual rules the chosen template must satisfy:

- **One shared cinematic pattern** across value screens — do *not* fork the layout per
  screen.
- Full-bleed **dark** background, **thin top progress indicator**, **one large product
  hero**, short copy at the bottom, **exactly one CTA per screen**.
- **No skip affordances. No card chrome or boxed surfaces.**
- Must collect required profile fields post-auth (separate required first and last name +
  demographics: birthday, bounded to ages 13–120, and gender).
- Notifications opt-in is anchored to a concrete value prop ("never miss a climb drop / get
  24-hour advance notice on new First Ascent opportunities") — never generic "enable
  notifications" housekeeping.

## What the onboarding must accomplish

Sell the competitive hook fast — *you're racing real people up real landmarks, and First
Ascents can never be reclaimed* — collect the required profile fields, prime, and convert
to a hard paywall. Assume a serious user; no tutorial scaffolding.

## Template direction (for whoever's browsing templates)

Aim at **premium, competitive, cinematic fitness onboarding** — dark, bold, full-bleed,
single-hero-per-screen, one CTA. Think the energy of Strava's competitive/segment framing
or Whoop / Apple Fitness+'s cinematic polish — **not** friendly/pastel/cartoon/
illustrated-mascot templates, and **not** multi-CTA "feature grid" intro screens.
