# Share sheet

The share sheet is two tabs, Presets and Stickers, in `AscendApp/Features/ShareSheet/`.
This file records the rules that are settled, so a later edit does not quietly re-litigate them.
The engineering shape is in the `ascend-share-sheet` skill.
The design source is the captain's own Presets and Stickers mockups.

## The wordmark

Every preset card carries the real `AscendWordmark` lockup, never ASCEND spelled as text.
The A is the brand accent.
The letters are white on a dark card and black on a light card.
On stickers the A is lime on White and Black, and white on Lime, Coral and Sky.
Brand lime is `#86D30A` everywhere on this sheet.

## Rank

A rank counts people, and the card says which population (`ascend-leaderboards`, The rank model).
The finish rank on a card is the frozen at-completion standing, never recomputed, so a reopened climb and its card say what they said at the finish.
A card without a standing hides Rank and drops the layouts that need it.
It never says global.
Totals ranks are the exception on purpose: weekly, monthly and yearly boards by steps are read live the first time Totals is opened in a sheet, and a rank that cannot be read is hidden.

## How a standing is worded

One rule in `ShareStandingWording` words a finish on every card and sticker, so two surfaces never say different things about the same finish.
In the top half of a field (`topShareLimit`, one in two, compared as exact fractions so 32nd of 64 is `TOP 50%` and 458th of 914 is not) the headline is `TOP 12%` and the caption is `OF 914 CLIMBERS`.
In the lower half the headline leads with the rank, `#806`, the caption is the same, and the footer keeps `BEAT 11%`.
A field smaller than 10 (`minimumFieldForPercent`) always leads with the rank, because `TOP 33% OF 3 CLIMBERS` is not a statement.
A field of one is the climb's first ascent: `#1` over `FIRST ASCENT`, and nothing about what it beat.
Tied climbers hold the same frozen position, so they read the same.
The rule reaches the Curve card's headline, the Rank card's percentile column (`BEAT 19%` where it would have claimed a percentile), the climb and monthly rank stickers' footers, and the bell-curve stickers' headlines.
The profile's `TOP 25% OF CLIMBERS` subtitle is a different standing and is not part of this.
On the Curve card the `YOU` tag sits as close to the marker as it can while staying wholly above the curve's line, clear of the dot and inside the curve's box, for any rank up to seven digits and a finish anywhere on the curve, the tails and the peak included (`PresetCurveLayout.tagFrame`).

## Floors

Floors are steps divided by 16 (`FloorsClimbed.stepsPerFloor`) for a Just Climb and a routine.
A landmark is the one deliberate exception: it keeps its building's own floor count, scaled to the share of the climb the attempt covered, so the card reads the same number Climb Detail shows.
That count is the published storey count, else the reference step count divided by 19.8 (`live-climb-content`), so a landmark card does not read steps divided by 16.
Totals use steps divided by 16.

## Splits

Splits follow the app's pace rule (`paceSplitDurationSeconds`: 60, 120, 300 or 600 seconds by duration).
A climb with no splits hides the Splits and Split table layouts.

## Best efforts

A card shows the climber's own top three per measure as a laurel and the real count, one per measure.
One effort is a laurel with a line.
The climber picks one.
There are no "2nd best ever" pills or other moments.

## Stickers

- **Tap copies, hold saves.**
  A tap puts a transparent `public.png` on the pasteboard; a hold of 0.55 seconds saves the PNG to Photos with add-only access.
  The long press wins exclusively over the tap, so a hold never also copies.
- Totals cover the current week, month and year only.
- One global font, colour and shadow applies to every sticker.
- Stickers have no background.

## Seasonal themes

Each theme has a window by local date: Halloween Oct 1-31, Thanksgiving-season autumn Nov 1-30, Holiday Dec 1-31, New Year's Jan 1-31.
Outside its window a seasonal option is not shown at all: not in the Presets Background panel, and not in the Stickers seasonal row.
A seasonal background a climber saved earlier falls back to the Black background once its window has closed.
The year is generated, never hard-coded.

## Fonts

Bold is Montserrat Black, Condensed is Barlow Condensed ExtraBold, Mono is JetBrains Mono ExtraBold and Serif is Instrument Serif.
The four families ship under the SIL Open Font License 1.1.
`docs/font-licenses.md` records each file, its author and its copyright notice, and `docs/licenses/OFL-1.1.txt` holds the licence text those notices go with.

## Swiping the cards

`PresetCardPager` is a custom drag pager built to the captain's handoff (`SWIPE_SPEC.md`), and `PresetPagerGeometry` holds every number so tests pin them.
The row follows the finger one for one with no animation while it is down, and the neighbours slide in with it.
Pulling past the first or last card moves the card at 45% of the finger and brings nothing in.
A release pages when the drag passes 60 points or the velocity passes 350 points a second in that direction, never by more than one card, and otherwise springs back.
The page change and the drag reset share one transaction, so the spring starts from where the finger let go.
Scale (1 down to 0.9), opacity (1 down to 0.45), the text parallax of 24 points a card and the shadow are all driven by a card's distance from the centre, continuously.
The page marks and the caption live in the pager so they follow the drag too: the active mark is an 18 x 6 pill that blends with the drag, and the caption cross-fades with a 6 point slide.
A light haptic fires when a new card lands and not on a spring-back.
VoiceOver gets one adjustable element that moves a card at a time, and Reduce Motion swaps the spring for a 0.2 second ease-out and drops the parallax.
A chosen photograph is framed by the same drag instead, so paging then goes through the marks or a tap on a neighbour.
Do not layer a `TabView` or a second gesture on the pager; the rubber band, the peeking neighbours and the continuous depth are not possible with one.

## Background tiles

Each tile in the Background panel is one tap target: the swatch, its caption and a 4 point margin on each side, at least 46 points wide and over 44 tall, with no gap between neighbours.
A swatch draws the card's real background, which is non-interactive, so the tile's `contentShape` is what makes the swatch answer a tap; without it only the caption's glyphs did.
The swatch is also laid out as exactly its own square, because a zoomed pattern clipped to a tile still lays out at the card's size and used to sit over the tiles beside it.
`PresetBackgroundRowHitTargetTests` pins the tile frames: 44 points each way, no overlap, no gap.

## Fitting numbers

A card draws at one fixed type size and is exported as an image, so no figure on it may wrap, drop a digit to a second line or end in an ellipsis.
That holds at the largest values a climb can reach: a 100 hour time, thousands of floors, a six digit rank in a seven digit pool.
Every layout shares one approach, in `PresetFitGeometry` (pure widths) with `PresetStatColumns`, `PresetBesideOrBelow` and `PresetHeadlineLine` (the layouts that apply it) and `presetOneLine` (the modifier every figure and label carries).
- **Stat rows** (Classic, Rank, Centered) keep their design gap while the columns fit. Past that the gap closes toward 8 points, then the labels give up width down to 60% of their size, and only then does the whole row scale, every column by the same factor.
- **A big number beside its caption** (the Classic steps, the Rank position, the Curve and Splits headlines) scales before its caption moves: the headlines by at most 15%, the others by at most half. Past that the caption drops to its own line under the number.
- **Minimal** may break between one stat and the next and never inside one, and the dot stays with the stat before it.
- A long rank number gets looser tracking, because tracking does not scale with the text and the design's -0.06em would overlap its digits.
- The card pins `dynamicTypeSize(.large)`, so the wordmark's scaled font cannot make the preview differ from the export for a climber running larger text.
`PresetFitGeometryTests` pins the rules, and `PresetCardFitTests` reads every layout through Vision at the captain's own figures and at the extremes, and fails when a figure is split or cut.
The Splits and Split table layouts draw one bar or row per split, so a climb with very many splits (a 24 hour one has 144) meets a different limit, which this section does not cover.

## Story

Story hands Instagram the card alone: the 1080 x 1080 rounded square as `com.instagram.sharedSticker.stickerImage`, corners transparent, with the app's bundle id as `source_application`.
There is no 9:16 canvas and no `backgroundImage`, because an opaque background image is what put a dark rectangle around the card on Instagram's side.
Instagram still supplies the Story's own backdrop behind a sticker; the app cannot remove it.
