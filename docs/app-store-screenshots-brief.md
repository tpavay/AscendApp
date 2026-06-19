# Ascend — App Store Screenshots Brief (for ChatGPT)

*Paste this whole file into ChatGPT. It's self-contained — you don't have my codebase.*

---

## 0. What I want from you

I'm building the App Store screenshot set for my iOS app, **Ascend**. Help me with:

1. **Generate the two "transformation" photos** (image generation) — these are real-world
   outcome photos with **no app interface**. Ready-to-paste prompts are in §7 and §9.
2. **Tighten the caption copy** for all screens, in the brand voice defined in §3.
3. **Recommend layout/framing** for the 5 feature screens (device frame vs. floating, caption
   placement, background treatment).

**Hard rule:** the 5 feature screens use *real captures from my app* — which I will provide.
**Do NOT invent, draw, or hallucinate app UI.** Faking the interface is misleading and gets
apps rejected. Your job on feature screens is copy + composition, not inventing screens.

---

## 1. What Ascend is

Ascend is a **competitive stair-stepper companion for iOS**. It turns every stepping session
into a race up real-world landmarks. You pick a landmark (Mt. Everest, Empire State Building,
Burj Khalifa), race in real time against other people's past attempts via headphone-motion
step tracking, and either hit the target step count (completion) or you don't.

**Core promise:** *Race the world up real landmarks. From your stair stepper.*

**The retention hook — First Ascent:** the first person ever to finish a climb holds its
**First Ascent** forever. Permanent prestige that can never be reclaimed, even after faster
climbers beat the time. Every new climb drop opens a fresh First Ascent slot.

## 2. Who it's for / NOT for

**For:** people who already use the stair stepper (or are about to) and want their work to
count — serious, goal-driven steppers chasing PRs, rank, and progress that compounds.

**NOT for** (keep captions on-niche — this matters):
- Not general fitness users who don't care about the stair stepper.
- Not a social network — no feed, no followers, no kudos.
- Not a generic "any workout" tracker.
- Not a passive tracker — every session is competitive context.

## 3. Brand voice (apply to every caption)

Niche-aggressive, declarative, confident — willing to lose readers who aren't the target.

- **Active verb at the front:** Climb. Race. Rank. Push. Track.
- **Imperative over invitational:** "Be the first" > "You could be the first."
- **No hedging** — cut maybe/perhaps/if you'd like.
- **Specific over abstract** — name landmarks, name numbers, name verbs.
- **The dare beats the invite.** Assume the user is serious. Don't soften "race."
- **Name the stair stepper — it's the niche *and* the #1 search keyword.** It must appear in
  both photo openers and in at least one feature caption (e.g. *"every step on the stepper,
  live"*). **Name it; don't explain it.** Never ship a full set that omits it — AI caption
  generators drop it by default.
- Keep headlines to **~3–6 words**. One idea per screen.

## 4. Visual identity

- **Dark-first and cinematic.** Full-bleed photography, readability overlays, bold type.
- **Accent:** electric lime `#86D30A` — used with discipline, never as a wash.
- **Medal tokens** (podium / prestige only): Gold `#D4AF37`, Silver `#C0C0C0`, Bronze `#CD7F32`.
- **Type:** Montserrat (Bold / SemiBold / Medium / Regular). Headlines = Montserrat Bold.
- **Mark:** an angular "A" that doubles as the letter A in the "Ascend" wordmark.
- Energy reference: Strava's competitive framing / Whoop / Apple Fitness+ cinematic polish.
  **Not** friendly/pastel/cartoon/mascot.

## 5. App Store screenshot specs

- **Primary size:** iPhone 6.9" — **1320 × 2868 px**, portrait. (Apple auto-scales this down
  to smaller iPhones, so one iPhone size usually covers it. 6.5" fallback: 1284 × 2778.)
- **iPad 13"** (only if iPad is supported): 2064 × 2752 px, portrait.
- **Up to 10** screenshots per localization. **The first 2–3 show in search without tapping** —
  so the transformation photos (the hook) lead.
- PNG or JPG, sRGB, **no transparency/alpha**, portrait.
- **ASO note:** since mid-2025 Apple **OCR-indexes the caption text** on screenshots — but it's
  the **lowest-weight** indexed field (app name > subtitle > keyword field > caption OCR). So
  **lock "stair stepper" in the app name / subtitle / keyword field first**, then reinforce it in
  the captions. Where it reads naturally, work in: *stair stepper, climb, leaderboard, step*.

---

## 6. THE STRUCTURE — 2 transformations, then 5 features

The set is ordered **outcome-first, app-second**: sell the real-world payoff with photography
before showing any interface.

> ### ⚠️ What a "transformation" screen IS (read carefully)
> A transformation screen = the **real-world OUTCOME**, sold with a **PHOTO**, and **ZERO app
> interface**. It is *not* a product screen, *not* an identity screen, *not* the app shown over
> a photo. Just a full-bleed photo + a short headline on a bottom scrim. The app does not appear
> until the feature screens.

Sequence (7 screens; flex to 6–8):

| # | Type | Screen | One-idea headline |
|---|------|--------|-------------------|
| 1 | Transformation (photo, no UI) | Stair-stepper effort | **Get fit on the stair stepper.** |
| 2 | Transformation (photo, no UI) | The summit / Everest | **Climb Everest from your stair stepper.** |
| 3 | Feature (real app capture) | Browse — globe of climbs | Race the world up real landmarks. |
| 4 | Feature (real app capture) | Live race + replay leaderboard | Race real climbers, step for step. |
| 5 | Feature (real app capture) | Per-climb leaderboard | Every step ranked. |
| 6 | Feature (real app capture) | First Ascent (gold) | Be the first. Claimed once — forever. |
| 7 | Feature (real app capture) | Records / Best Efforts | Your record book. And it's climbing. |

**Narrative arc:** *You, putting in the work (1) → the epic payoff (2) → then the app proves how:
discover landmarks (3) → race live (4) → climb the ranks (5) → claim a First Ascent (6) → build
a record book (7).*

---

## 7. Screen-by-screen

### Screen 1 — Transformation: "Get fit on the stair stepper."
- **Image (generate this):** see prompt **A** in §9. Dark, moody, editorial photo of someone
  mid-session on a stair-stepper machine. No UI, no text in the image.
- **Headline overlay (added later in Figma):** *Get fit on the stair stepper.*
- Bottom third should stay darker/cleaner for the headline scrim.

### Screen 2 — Transformation: "Climb Everest from your stair stepper."
- **Image (generate this):** see prompt **B** in §9. Cinematic Everest/Himalayan summit vista.
  No UI, no text in the image.
- **Headline overlay:** *Climb Everest from your stair stepper.*

### Screen 3 — Feature: Browse (globe of climbs)
- **Source:** real app capture (my asset `OnboardingGlobalClimbsScreenshot`). Do not redraw it.
- **Caption options:** "Race the world up real landmarks." · "Pick a landmark. Start climbing." ·
  "A globe of climbs. Pick your summit."

### Screen 4 — Feature: Live race (replay leaderboard)
- **Source:** real capture of the live climb screen (I capture this in-app). Shows elapsed time,
  target steps, and the user's row racing other climbers' past attempts in real time.
- **Caption options:** "Race real climbers, step for step." · "Their past attempts are your pace
  car." · "Real-time. Real climbers. Real stakes."

### Screen 5 — Feature: Per-climb leaderboard
- **Source:** real app capture (`OnboardingEmpireLeaderboardScreenshot`). Top-3 in medal colors.
- **Caption options:** "Every step ranked." · "Climb the leaderboard. Literally." · "Top 3 or
  keep climbing."

### Screen 6 — Feature: First Ascent (the prestige hook)
- **Source:** real app capture (`FirstAscentBadgeDetailed`) — lean into the **gold**.
- **Caption options:** "Be the first. Claimed once — forever." · "First Ascents never get
  reclaimed." · "World first. Held forever."

### Screen 7 — Feature: Records / Best Efforts
- **Source:** real app capture (`OnboardingProgressScreenshot`).
- **Caption options:** "Your record book. And it's climbing." · "Break your records. Then break
  them again." · "Most steps. Longest climb. Highest pace."

---

## 8. Caption discipline checklist

For every headline you propose, confirm:
- [ ] Leads with an active verb or a concrete noun (landmark / number).
- [ ] ≤ ~6 words, one idea.
- [ ] No hedging, no tutorial tone, no "explore/discover/learn."
- [ ] On-niche (stair stepper / climb / race / rank) — not generic fitness.
- [ ] Reads as a dare, not an invitation.

---

## 9. Ready-to-paste image-generation prompts (the 2 transformation photos)

Generate **vertical portrait** (target 1320 × 2868 / ~9:19.5; if the model can't, make it tall
9:16 and I'll crop). **No text, no logos, no app UI, no watermarks.** Leave the **lower third
darker and uncluttered** for a headline. Generate 3–4 variations of each.

**PROMPT A — stair-stepper effort (Screen 1):**
> Cinematic, moody editorial photograph of a lean, athletic person mid-workout on a commercial
> stair-stepper / stair-climber machine in a dark gym. Low side angle, dramatic single-source rim
> lighting, deep shadows, visible effort and sweat, sense of motion in the legs. Deep teal-to-black
> background with subtle volumetric haze; a single restrained electric-lime (#86D30A) light accent
> in the rim/edge lighting. Shot on 35mm, shallow depth of field, high contrast, premium and
> serious — Nike / Whoop campaign energy. Vertical portrait composition with clean, darker negative
> space in the lower third for a text overlay. No text, no logos, no on-screen interface, no
> watermark.

*Variations to try: add a weighted vest; change the athlete; tighter crop on the legs/steps in
motion; cooler vs. warmer key light.*

**PROMPT B — the summit payoff (Screen 2):**
> Cinematic, aspirational photograph of a lone mountaineer on a high Himalayan summit ridge at
> dawn, Everest-scale snow peaks and a vast sea of clouds below. Cold blue-and-gold light, wind,
> immense scale and altitude, a single small figure for scale, a quiet sense of achievement.
> National Geographic / editorial style, ultra-wide vista, high dynamic range, crisp and premium.
> Vertical portrait composition with clean, darker negative space in the lower third for a
> headline. No text, no logos, no on-screen interface, no watermark.

*Variations: golden-hour vs. blue-hour; figure facing away (POV); more dramatic cloud sea; an
alternate landmark outcome (Empire State rooftop at night, Burj Khalifa) if I want to A/B.*

---

## 10. Do / Don't

**Do**
- Generate the two transformation photos with clean negative space for headlines.
- Propose 2–3 caption options per screen in the brand voice.
- Suggest a consistent feature-screen treatment (frame, background, caption position) so all 5
  feel like one set.

**Don't**
- Don't render, redraw, or invent any app UI for the feature screens — those are real captures
  I provide.
- Don't drift to generic-fitness or social-network framing.
- Don't put medal gold/silver/bronze anywhere except the First Ascent / leaderboard prestige
  moments. Lime is the only everyday accent, used sparingly.
- Don't add body text paragraphs — one short headline per screen.

## 11. What I'll provide

- The 5 real feature-screen captures (named assets above).
- Final type composition happens in my Figma file (Montserrat styles already set up) — so for
  feature screens I mainly need your **copy + layout direction**, and for transformations I need
  the **photos** (and I'll overlay the headline myself).
