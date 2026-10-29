---
name: ascend-share-sheet
description: Use when working on Ascend sharing - the share sheet and its Presets and Stickers tabs, the preset card canvas and its nine layouts, backgrounds and seasonal themes, transparent stat stickers, the copy-to-clipboard and hold-to-save gestures, Instagram Story hand-off, Photos permission at share time, or the rank, floors, splits and best-effort figures a card asserts. Covers the sheet that replaced the user-composed share composer.
---

# Share Sheet Architecture

Sharing in Ascend is one sheet with two tabs, opened from the Live Climb completion summary and from Workout Detail.
`AscendApp/Features/ShareSheet/` owns all of it.
**`docs/share-sheet.md` owns the rules the design settled** (wordmark colours, frozen ranks, floors, splits, best efforts, seasonal windows, the gestures).
Read it before editing a card or a sticker; do not re-litigate those rules here.

## The two tabs - keep them independent

- **Presets** is a finished card.
  `PresetCardCanvas` draws a 310 x 310 design-space card that `ShareSheetExporter.renderCard` scales to 1080 x 1080.
  A card is a layout, a background, a font, an accent and a chip set, all stored in `PresetPreferences` and read back through `PresetPreferencesStore`.
  Actions: Story, Copy, Save, More.
- **Stickers** are transparent PNGs for the climber to drop on their own photo or video.
  A tap copies the PNG, a hold saves it.
  Stickers share one global `StickerStyle` (font, colour, shadow) and never carry a background.
- Both tabs read one `ShareSheetSubject`, built once by `ShareSheetSubjectBuilder` from the `Workout`, the frozen standing and the climb catalogue.
  A view never reads a `Workout` for a number a card prints.

## The standing a card asserts

**What a rank means is stated once in `ascend-leaderboards` under The rank model.**
A card is statement 3: a climb's summary, reopened, still says what it said, and the card carries that same time and that same number.
Only the frozen at-completion standing is forwarded to `ShareSheetSubjectBuilder`; the sheet never fetches a fresh one for a finished climb.
A card without a standing hides Rank and the layouts that need it, and degrades to less, never to empty.
`SavedClimbShareRankTests` anchors the saved-climb path.

## One renderer per tab

Everything drawn is a SwiftUI view rendered by `ImageRenderer`, so what the climber previews is what exports.
A card's content is fixed-size (`Font.custom(_:fixedSize:)`): the export renders at the default text size for everyone, and a card that scaled would show the author something the export cannot reproduce.
The sheet's own chrome (tabs, panels, toast) uses `Font.montserrat*` and scales with Dynamic Type.
Do not unify the two in either direction.
Any new card-content view needs `.dynamicTypeSize(.large)` where `AscendWordmark` is drawn, because the wordmark scales with the reader's text size unless something pins it.

## Layouts are data-gated

`PresetLayout.available(hasRank:rankStatOn:hasSplits:)` decides which of the nine layouts a climb may use.
A layout that needs a rank or splits is hidden when the subject has none, never drawn empty.
Adding a layout is a `PresetLayout` case, its view, and a line in the availability rule - never a branch in `PresetCardView`.

## Backgrounds

Flat colours and the generated textures are drawn, not bundled.
Seasonal backgrounds are the only bundled art (`Assets.xcassets/Seasonal`), gated by `SeasonalTheme` windows read from the device's local date.
A saved seasonal background falls back to Black outside its window.
Photo backgrounds come from `PresetPhotoLibrary`; pan and pinch framing is `photoScale` and `photoOffset` on the preferences, applied by `PresetCardArtwork`.
A filled image reports the size it scaled to, not the size it was offered - draw it as an `.overlay` on `Color.clear` (see `PresetFilledImage` and the CLAUDE.md tripwire).

## Drawn marks are masked

The heart-rate polyline, split bars, calendar, bell curve and the stickers that draw a measurement are marks Sentry cannot see.
Apply `View.sentryMasked()` inside the view's own definition and add the surface to both `SentryMaskingEvidenceTests` and `SentryMaskInteractionTests` (`docs/sentry-setup.md`).

## Cost rules

- Resolution never happens in the render path.
  The subject, the splits, the best efforts and the totals are built once; a view reads values.
- `ShareTotalsRepository` is a bounded fetch with `propertiesToFetch`, for the current week, month and year only.
  Never a whole-store scan.
- A standing read for Totals goes through `ShareStandingReading` with `withLeaderboardTimeout`: one own-document read and two count aggregations per board, read once per sheet when Totals first opens, and a rank that cannot be read is hidden.

## Boundaries

- Photos: reading a library photo for a background asks `.readWrite` at the moment the climber opens the photo sheet; saving asks `.addOnly` at the first save.
  Never in onboarding.
  `NSPhotoLibraryUsageDescription` is stored in four places that change together (`ascend-privacy-manifest`).
- Story hands Instagram the card alone as `com.instagram.sharedSticker.stickerImage` (1080 x 1080, transparent corners), the bundle id as `source_application`.
  Never a `backgroundImage` and never a 9:16 canvas: Instagram draws the rounded square only.
  Stickers never go to Story directly; they are clipboard and Photos only.
- Everything is bundled and rendered on device.
  No remote template service, no server-rendered images, no remote-configured layouts.
- The Live Climb completion summary stays the emotional payoff; its Share button opens this sheet and never replaces the summary.
- Analytics: the screen only, `TelemetryScreenName.shareComposer` (the raw value `share_composer` is kept so the funnel stays continuous).
- Legacy `share-card-templates/...` objects may still sit in Storage; nothing here reads them.
