# Share cards

The four finalized cards - Result, Poster, Sticker, Standing - are entries in
`AscendApp/Features/ShareComposer/Resources/share-card-templates-v1.json`, drawn
by the one interpreter in `ShareCardRenderer`.
This file records the rules that are settled, so a later edit does not quietly
re-litigate them.
Everything here is enforced by tests; the anchor test for each rule is named
beside it.

## The wordmark

Every card carries the real `AscendWordmark` lockup, small, fixed at
bottom-centre, drawn by `ShareCardTemplateView` rather than by any template.
A template chooses only its tint.
The card's content is framed to `designSize.height - wordmarkClearance` and
clipped, so no element can reach into the band or overlap the mark, at any
supported Dynamic Type size or on the smallest supported canvas.
Never spell the wordmark as plain text, never move it, never omit it.
Anchor: `FinalizedShareCardSetEvidenceTests.theWordmarkSitsInAnIdenticalProtectedBandOnEveryCard`,
and the payload check in `scripts/test/share-card-templates.test.mjs`.

## No dead space above the band

The clearance band is the only gap at the bottom of a card.
Result and Standing size their lower panel to what it actually draws and let the
artwork take every remaining point above the band; the panel's own 12pt bottom
padding is the whole separation.
The measured gap between the last content row and the top of the band stays
within 24 design points - about 3% of the card.
A fixed panel height, or a reserved slot for something a variant does not draw,
is how this regressed once already.
A reserved slot opens its void between two content rows rather than under the
last one, so the tallest run of identical rows anywhere above the band is
measured too, and stays under 48 design points.
Anchors: `FinalizedShareCardSetEvidenceTests.theLastContentRowStaysAgainstTheWordmarkBandOnResultAndStanding`
and `FinalizedShareCardSetEvidenceTests.noVariantReservesASlotItDoesNotDraw`.

## Rank

The rank tab bleeds off the card's right edge by design: only the span from its
leading inset to the card edge is ever drawn.
It reads `4th of 1,284`.
It never says **global** - the field is the climb's leaderboard, and naming it
"global" claims a scope the card cannot back.
A field of one is not `1st of 1`: it becomes the `FirstAscentBadgeDetailed` icon
and `FIRST ASCENT`, on every card.
Which standing may reach this tab is owned by `ascend-share-composer`: only the
frozen at-completion one may be forwarded.
Anchor: `ShareCardRankTabView`, and the "never says global" check in
`scripts/test/share-card-templates.test.mjs`.

## Splits

Result shows exactly five split rows for every tower, short or long, labelled by
step range.
Only the ranges change between a 149-step stairwell and a 1,576-step tower; the
row count never does.
Anchor: `FinalizedShareCardSetEvidenceTests.theResultCardShowsFiveStepRangesForShortAndLongTowers`.

## FLOORS

`FLOORS` sits beside `STEPS` and `AVG SPM`, so it reports this attempt, not the
tower.
It is the catalogue floor count scaled by the attempt's share of the catalogue
reference step count, which makes a completed climb read the same number the
climb's detail screen shows.
An overshoot is left alone - a climber who kept going past the summit did the
extra floors.
Anchor: `ShareStatResolver.attemptFloors`.

## Standing

The hero is the percentile, and the wording is exactly
`FASTER THAN N% OF <field> CLIMBERS`.
There is no lower clamp: last place beat nobody and the card says 0%, because it
reports the leaderboard rather than rounding the result up to flatter it.
The distribution curve is filled for the share of the field beaten, with
`SLOWER` and `FASTER` axis labels.
Standing is offered only when a standing resolves - it declares
`"requires": ["climb", "standing"]`, and `ShareCardTemplateStore` withholds it
otherwise rather than drawing an empty card.
A First Ascent has no field to plot, so the curve is replaced by
`NOBODY HAS CLIMBED THIS TOWER BEFORE YOU` and its slot collapses; the
`standing` element's `height` is deliberately absent from the payload so the
visualization sizes to what it draws.
Anchors: `ResolvedShareStandingTests`, `ShareCardTemplateStoreTests`,
`FinalizedShareCardSetEvidenceTests.standingRendersAtEveryPercentile`.
