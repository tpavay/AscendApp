# Ascend - App Store screenshots brief

> **Status: the en-US iPhone set has shipped.**
> The delivered files, the renderer that produces them, and the durable image sources live under `AppStoreAssets/`.
> `AppStoreAssets/README.md` owns the per-screen sources, geometry, and output contract; `AppStoreAssets/qa/review.md` owns the set-level review evidence and per-screen boundary numbers.
> Where this brief disagrees with those two documents, they win.
>
> This file is the reusable brief: brand voice, caption discipline, the output contract, the production process, the quality rules the set must hold to, and the image-generation prompts that produced the two transformation photographs.
> Use it when producing a new localization, re-shooting the set, or replacing a capture.

---

## 0. How to use this file

Read sections 1 through 4 for what Ascend is and how its copy and visuals must sound and look.
Read sections 5 through 7 for the hard output, production, and quality constraints any new set must satisfy.
Read sections 8 and 9 when writing captions or generating new photography.
Section 10 is planning history and carries no instructions.

The two approved transformation photographs already exist and are preserved at `AppStoreAssets/sources/01-stair-stepper-effort.png` and `AppStoreAssets/sources/02-everest-summit.png`.
Regenerate them only for a genuinely new concept; the prompts in section 9 are what produced them.

---

## 1. What Ascend is

Ascend is a **stair stepper racing app for iOS**. Racing is the product; measuring the
session is a byproduct. You pick a real tower, race its actual step count against every
attempt already posted on it via headphone-motion step counting, and either hit the target
(completion) or you don't.

`CLAUDE.md` ("What Is Ascend") owns the positioning statement and the tower-running market
framing behind it. Read it there rather than from a second copy.

**Core promise:** *Race real towers. From any gym.*

**The retention hook - First Ascent:** the first person ever to finish a climb holds its
**First Ascent** forever. Permanent prestige that can never be reclaimed, even after faster
climbers beat the time. Every new climb drop opens a fresh First Ascent slot.

## 2. Who it's for / NOT for

**For:** people who already use the stair stepper (or are about to) and want their work to
count - serious, goal-driven steppers chasing PRs, rank, and progress that compounds.

**NOT for:** `CLAUDE.md` ("What Ascend Is NOT") owns the exclusion list and
`ascend-brand-voice` owns the rationale. Keep captions on-niche - this matters - and never
caption a feature Ascend does not have. Ascend is not a logger or an importer, so no
caption may promise manual entry, Apple Health workout import, or generic workout tracking.

## 3. Brand voice (apply to every caption)

`ascend-brand-voice` owns the voice and every caption must apply it; it is not restated
here. Section 8 is the per-caption checklist. Two rules specific to this set:

- **Name the stair stepper - it's the niche *and* the #1 search keyword.** It must appear in
  both photo openers and in at least one feature caption (e.g. *"every step on the stepper,
  live"*). **Name it; don't explain it.** Never ship a full set that omits it - AI caption
  generators drop it by default.
- Keep headlines to **~3-6 words**. One idea per screen.

## 4. Visual identity

- **Dark-first and cinematic.** Full-bleed photography, readability overlays, bold type.
- **Accent:** electric lime `#86D30A` - used with discipline, never as a wash.
- **Medal tokens** (podium / prestige only): Gold `#D4AF37`, Silver `#C0C0C0`, Bronze `#CD7F32`.
- **Type:** Montserrat (Bold / SemiBold / Medium / Regular). Headlines = Montserrat Bold.
- **Mark:** an angular "A" that doubles as the letter A in the "Ascend" wordmark.
- Energy reference: Strava's competitive framing / Whoop / Apple Fitness+ cinematic polish.
  **Not** friendly/pastel/cartoon/mascot.

---

## 5. Output contract

- **iPhone only.** The app target is iPhone-only, so there is no iPad set.
- **Exactly 1320 x 2868 px, portrait** (iPhone 6.9"). Apple scales that one size down for smaller iPhones.
- **Seven images** per localization. Apple allows up to 10; the first two or three show in search without tapping, which is why the transformation photographs lead.
- **PNG, sRGB, no alpha channel.** The renderer asserts all four of file count, dimensions, color space, and absence of alpha before it finishes.
- **ASO note:** since mid-2025 Apple OCR-indexes screenshot caption text, but it is the lowest-weight indexed field (app name > subtitle > keyword field > caption OCR). Lock "stair stepper" into the app name, subtitle, and keyword field first, then reinforce it in the captions. Where it reads naturally, work in: *stair stepper, climb, leaderboard, step*.

---

## 6. How the set is produced

`AppStoreAssets/render-screenshots.mjs` is the only thing that produces the upload files.
There is no Figma composition step and no hand-editing of a rendered PNG; a change to the set is a change to the renderer or to a source image.

Every image input is a durable copy under `AppStoreAssets/sources/`: the two approved transformation photographs and one real app capture per screen.
Those captures come from a staging build pointed at a seeded environment; `docs/staging-content-capture.md` owns the one command that puts staging into a state worth capturing, and what that state contains.
Nothing is read out of `web/` except the Sharp package, so re-cropping or replacing a website marketing image cannot change these renders.

```bash
npm --prefix web ci
node AppStoreAssets/render-screenshots.mjs
```

Outputs land in `AppStoreAssets/screenshots/iphone-6.9-en-US/`, and the run also writes the seven-screen contact sheet to `AppStoreAssets/qa/app-store-contact-sheet.png`.
Every path other than the Sharp lookup is derived from the script's own location, so the working directory does not matter.

Framing constraints the renderer enforces (per-screen numbers are in `AppStoreAssets/README.md` and `AppStoreAssets/qa/review.md` - do not restate them here):

- Each capture is a whole 19.5:9 iPhone screen, the phone screen is 1012px wide, and scaling is width-driven only, so no column of app UI is ever lost sideways.
- Each screen declares the first capture row clear of that device's own status chrome, the last row that must be whole on screen, and the first row that must not appear at all. The renderer refuses to build a body that starts inside the status chrome or whose bottom edge falls outside that gap, so nothing can be sliced.
- Body height is therefore derived per screen, because the captures are scrolled to different places. The devices are centred in one band and the renderer rejects a height spread wide enough to break the illusion of one phone.
- One status-bar master is reused on all seven screens, supplying the same clock, signal, Wi-Fi, battery, and Dynamic Island pill.
- A screen whose capture has no chrome-free surface left below its content bleeds off the bottom of the canvas rather than being padded to a full device. Bleeding is always preferred to inventing pixels.

---

## 7. Quality rules the set must hold to

These are non-negotiable and were established the expensive way. Check every one before a set ships.

- **Exact size, iPhone only.** Every file exactly 1320 x 2868, no other device family.
- **Uniform status bar.** Same clock, full signal, full Wi-Fi, full battery, and exactly one correctly proportioned Dynamic Island pill on every screen. No capture's own status chrome survives into a body.
- **No truncated UI, horizontally or vertically.** No card, row, glyph, icon, or control sliced at any edge.
- **No disabled or inactive CTAs.** A primary action shown in the set must be shown enabled and genuinely enabled in the capture.
- **Nothing fabricated.** No invented pixels, padding, controls, or data, and no composite that implies an app state the app did not render. Real captures only; never redraw or regenerate app UI.
- **Headlines, imagery, and numbers must agree** within a screen and across the set. If two screens show the same climb, their step counts, ranks, and times must reconcile.
- **Judge the set from the contact sheet, not screen by screen.** Set-level review is mandatory; balance, repetition, and numeric contradictions only show up side by side.

Two further copy rules from the same discipline:

- Medal gold/silver/bronze appear only at podium and First Ascent prestige moments. Lime is the only everyday accent, used sparingly.
- One short headline per screen. No body-text paragraphs.

---

## 8. Caption discipline checklist

For every headline you propose, confirm:
- [ ] Leads with an active verb or a concrete noun (landmark / number).
- [ ] <= ~6 words, one idea.
- [ ] No hedging, no tutorial tone, no "explore/discover/learn."
- [ ] On-niche (stair stepper / climb / race / rank) - not generic fitness.
- [ ] Reads as a dare, not an invitation.

---

## 9. Image-generation prompts (the two transformation photographs)

The shipped photographs came from these prompts and are preserved under `AppStoreAssets/sources/`.
Only regenerate for a new concept.

Generate **vertical portrait** (target 1320 x 2868 / ~9:19.5; if the model can't, make it tall
9:16 and crop). **No text, no logos, no app UI, no watermarks.** Leave the **lower third
darker and uncluttered** for a headline. Generate 3-4 variations of each.

**PROMPT A - stair-stepper effort (screen 01):**
> Cinematic, moody editorial photograph of a lean, athletic person mid-workout on a commercial
> stair-stepper / stair-climber machine in a dark gym. Low side angle, dramatic single-source rim
> lighting, deep shadows, visible effort and sweat, sense of motion in the legs. Deep teal-to-black
> background with subtle volumetric haze; a single restrained electric-lime (#86D30A) light accent
> in the rim/edge lighting. Shot on 35mm, shallow depth of field, high contrast, premium and
> serious - Nike / Whoop campaign energy. Vertical portrait composition with clean, darker negative
> space in the lower third for a text overlay. No text, no logos, no on-screen interface, no
> watermark.

*Variations to try: add a weighted vest; change the athlete; tighter crop on the legs/steps in
motion; cooler vs. warmer key light.*

**PROMPT B - the summit payoff (screen 02):**
> Cinematic, aspirational photograph of a lone mountaineer on a high Himalayan summit ridge at
> dawn, Everest-scale snow peaks and a vast sea of clouds below. Cold blue-and-gold light, wind,
> immense scale and altitude, a single small figure for scale, a quiet sense of achievement.
> National Geographic / editorial style, ultra-wide vista, high dynamic range, crisp and premium.
> Vertical portrait composition with clean, darker negative space in the lower third for a
> headline. No text, no logos, no on-screen interface, no watermark.

*Variations: golden-hour vs. blue-hour; figure facing away (POV); more dramatic cloud sea; an
alternate landmark outcome (Empire State rooftop at night, Burj Khalifa) if I want to A/B.*

---

## 10. Planning history: the seven-screen concepts

This section records the original plan and its intent. It is history, not instruction.

The set was ordered outcome-first, app-second: sell the real-world payoff with photography before showing the interface.

| # | Concept | One-idea headline |
|---|---------|-------------------|
| 01 | Stair-stepper effort | Get fit on the stair stepper. |
| 02 | The summit / Everest | Climb Everest from your stair stepper. |
| 03 | Browse - globe of climbs | Race the world up real landmarks. |
| 04 | Live race + replay leaderboard | Race real climbers, step for step. |
| 05 | Per-climb leaderboard | Every step ranked. |
| 06 | First Ascent | Be the first. Claimed once - forever. |
| 07 | Records / Best Efforts | Your record book. And it's climbing. |

**Narrative arc:** *You, putting in the work (01) -> the epic payoff (02) -> then the app proves how:
discover landmarks (03) -> race live (04) -> climb the ranks (05) -> claim a First Ascent (06) -> build
a record book (07).*

Two things changed between plan and delivery.
Screens 01 and 02 were planned as photography with zero app interface; they shipped with the photograph full-bleed and genuine Ascend UI composited over it, which sells the outcome and proves the product on the same screen.
The plan also assumed onboarding image assets would stand in for feature screens; the shipped set uses purpose-taken captures of the running app instead, listed per screen in `AppStoreAssets/README.md`.

The shipped headlines are the renderer's own screen table in `AppStoreAssets/render-screenshots.mjs`.
