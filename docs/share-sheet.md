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
The four families ship under the SIL Open Font License 1.1; `docs/font-licenses.md` records each file and its author.

## Story

Story is unchanged from before the redesign: the card on a 1080 x 1920 dark canvas, handed to Instagram with the app's bundle id as `source_application`.
