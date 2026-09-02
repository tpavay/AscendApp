---
name: ascend-share-composer
description: Use when working on Ascend sharing - the share composer canvas, the declarative share-card format and its one interpreter, card templates and their bundled JSON, background presets, pre-formatted stat clusters, stat stickers and label placement, sticker gestures and snapping, photo and video export, AVFoundation compositing, Instagram Story sharing, or Photos permission at share time. Covers the user-composed canvas model that replaced fixed share-card carousels.
paths:
  - AscendApp/Features/ShareComposer/**
  - scripts/validate-share-card-templates.mjs
  - scripts/test/share-card-templates.test.mjs
---

# Share Composer Architecture

Sharing in Ascend is a **user-composed canvas**, not a gallery of pre-designed cards. The user picks a background (their own photo/video or a preset), then drops stat "stickers" onto it and arranges them freely - the Instagram Story editor model. This replaces the older "carousel of fixed share-card variants" approach. Every share surface in the app (workout detail, Live Climb completion summary) routes into the same composer.

## The two composable inputs - keep them independent
- **Background** = what fills the canvas. Sources: the user's Camera Roll (photo or video) or a bundled/known **background preset** (in code a bare `preset` means a stat cluster, so spell this one out). For a Live Climb, the climb's bespoke share card becomes one of those background presets - it's no longer a parallel share path. Backgrounds and stats are decoupled: a background is just a backing layer, never bundled with baked-in stats.
- **Stat stickers** = draggable overlays the user adds on top. A sticker carries one stat (Steps, Duration, Calories, Avg SPM, Heart Rate, Climb Rank/"Nth finisher", Climb Name, Date, etc.), optionally composited with more, or a whole pre-formatted **stat cluster** (see *Stat clusters*), and is drawn by the card format - see *One card format, one interpreter*. The user adds as many as they want, in any arrangement.

## Composer interaction model
- Each sticker supports simultaneous pan / pinch-scale / rotate via composed SwiftUI gestures. Drag-to-bottom reveals a trash zone; release over it deletes the sticker.
- Alignment: center + edge snap guides (V1). Full Instagram-grade snapping (third-lines, between-sticker magnetism) is deferred.
- **Editing is SwiftUI-over-player; export is the only AVFoundation work.** While composing, the canvas is a SwiftUI `ZStack` of the background (an `Image` or an `AVPlayer`-backed video) with draggable sticker views on top - no composition happens during editing. Composition runs ONCE at save/share time.

## Camera Roll scope - album and date

The Camera Roll tab is scoped, not one unfiltered roll.
`ShareCameraRollScope` composes an album selection with an optional `ShareDateWindow` into a single PhotoKit predicate, so the two scopes stay genuinely independent and neither overwrites the other.
The three source pills (Camera Roll / Presets / Recaps) are untouched at fixed width; a text-only underline filter row sits under them and a calendar button sits in the header.
Each rule below is carried in its own type's doc comments and pinned by `AscendAppTests/ShareCameraRollScopeTests.swift` - read those before changing an ordering, a window, or a fetch.

- **`All Albums` sits second, directly right of `Recents` - not last.** Measured at Montserrat's real widths only about four items fit before the row scrolls, so anywhere further along a long album name pushes off the one item that leads everywhere else. Opening an album from the All Albums grid turns that same slot into a back item, and while it does, that album is dropped from the shortcuts further along so it cannot appear twice. `ShareScopeShortcuts` is pure for exactly that reason - the ordering is testable without a photo library or a view tree.
- **The album is persisted across launches; the date deliberately never is.** An album is a place, a date is a moment - persisting one opens the composer in October still scoped to August onto an empty grid. Only an album selection writes the stored scope, and only Recents clears it: browsing the album grid and backing out is not a choice.
- **The date sheet's primary button IS the live count** (`SHOW 312 PHOTOS`, disabled `NO PHOTOS IN MARCH 2024`), counted inside the album already selected. A wheel picker otherwise lets a climber assemble a combination that holds nothing and only says so afterwards. `.wheel` draws its own selection band and does not permit restyling; only the row content is ours.
- **The calendar button appears exactly when photos are on screen.** It is absent on the All Albums grid (browsing albums, nothing to date-filter yet) and on Presets and Recaps.
- **Albums are fetched only under `.authorized`.** PhotoKit cannot fetch user albums at all under `.limited`, so the call is skipped rather than made and found empty - an empty result there is indistinguishable from owning no albums, and the two need opposite screens.
- **iCloud shared albums, My Photo Stream, and Hidden are excluded.** The first two are cloud-only, so opening one starts a network download inside a picker with no loading state for it, and limited access cannot see them at all. Hidden needs `includeHiddenAssets` and would be a privacy incident with a tile on it.
- Square photo cells with a 3pt gap are the picker's settled geometry, kept deliberately over an edge-to-edge 3:4 grid even though the share canvas is 9:19.5 portrait.

## One card format, one interpreter

Everything drawn on a share - a sticker on the canvas, a full recap template, every exported pixel - is a `ShareCardNode` tree rendered by `ShareCardRenderer`. **Never add a second renderer.** The composer's worst bug came from having two: a per-stat setting the chosen one did not accept was silently discarded, so a label placed on the left jumped back on top the moment a stat was added.

- **Format**: `Models/ShareCardFormat.swift` (elements + modifiers), `ShareCardStyling.swift` (colors, fills, typography), `ShareCardLabel.swift` (placement + policy). SwiftUI-free and `Codable`; `Views/ShareCardStyleResolvers.swift` turns it into `Font`/`Color`.
- **Interpreter**: `Views/ShareCardRenderer.swift` - one `switch`, one modifier order (frame, shadow, padding, background, border, rotation, opacity). A layout that needs a different order nests a node; the schema does not grow a knob.
- **Stickers**: `Models/ShareStickerCardBuilder.swift` turns a `ShareStickerInstance` into that same tree. Pure, so arrangement rules are testable without a view tree.
- **Templates**: `Resources/share-card-templates-v1.json`. Adding a card is a JSON edit plus a screenshot - **no Swift**. `scripts/validate-share-card-templates.mjs` reads the renderer's vocabulary out of the Swift sources and fails CI on a typo'd stat or element, and `scripts/test/share-card-templates.test.mjs` fails on a template that spells the brand as text instead of leaving the lockup to `ShareCardTemplateView` (the branding rule is `ascend-design-system`'s).
- The bundled set is the four finalized cards - Result, Poster, Sticker, Standing. **`docs/share-cards.md` owns the rules those cards settled** (the fixed wordmark band, the rank tab and its First Ascent form, the five step-range splits, FLOORS, and Standing's percentile wording). Read it before editing a card; do not re-litigate those rules here.
- A template declares what it cannot be drawn without in `requires` (`climb`, `standing`); `ShareCardTemplateStore` withholds a card whose requirements the composer cannot satisfy rather than offering an empty frame.

**The schema is closed** - a fixed set of element types chosen by a Swift `switch`, no expression language, no escape hatch that takes a script. That line is what keeps a future remote payload inside App Review 2.5.2.

**Card content does not scale with Dynamic Type; composer chrome does.** `ShareStickerFont.swiftUIFont` uses `Font.custom(_:fixedSize:)` because the exported image renders at the default text size for everyone - a canvas that scaled would show the author something the export cannot reproduce, and an export that scaled would make one template produce a different image per reader.
The composer's own chrome - the add sheet, the font and structure pickers, action pills, toasts, the background picker - uses `Font.montserrat*` (`relativeTo:`) and **must keep scaling**; that is reading UI, not card content.
Do not unify the two in either direction.
The trap is that `AscendWordmark` is drawn with a scaling face, so the canvas lockup obeys the reader's text size unless something pins it: `ShareCardTemplateView` pins the whole card, `ShareExportCanvas` pins itself, and the live canvas pins the lockup alone because the chrome around it must keep scaling.
Any new card-content view under the composer needs the same `.dynamicTypeSize(.large)`.

## The standing a card asserts

**What a rank means is stated once in `ascend-leaderboards` under The rank model.** A share card is statement 3: a climb's summary, reopened, still says what it said, and the card carries that same time and that same number.

Rank is what Ascend shares, so it is an input the entry point supplies - not something the composer looks up.
`ShareComposerView(climbRank:climbRankTotal:)` deliberately carries **no default**: a call site that silently omitted it is exactly how the saved-climb path shipped with no rank cluster, no rank stickers and no recap rank tab.
All three come off the one missing pair - `ShareStatResolver` returns nil, so `availablePresets()`, `climbStats()` and the `standing` requirement drop together - so a new entry point has to pass `nil` on purpose.

- **Only the frozen `.atCompletion` standing may be forwarded.**
  A card is published and keeps asserting its number after the board moves, while the screen behind it is free to keep showing a recomputed one; the two are supposed to differ.
  See `LiveClimbSummaryRankHero.Standing.frozen`, and the basis rules in `ascend-live-climbs`.
- **One source, never a second fetch.**
  The completion summary and a saved climb both read the frozen `completionSnapshots` answer through `CompletedClimbRankService`; the saved path wraps it in `SavedClimbShareStanding`, seeded synchronously on the Share tap so a device that already holds the snapshot draws the rank in the composer's first frame.
- **A standing that lands after the composer opens still has to reach every surface.**
  `setClimbRank` drops the memoized derived data, the recap preview is rebuilt, and an already-baked recap is redrawn - a bake is a snapshot, so that image would otherwise keep asserting the rank tab it was drawn without.
  `ShareRecapBakeState` owns that ordering and keeps a silent redraw apart from a render the climber asked for: only the latter dims the canvas, and a tap arriving during a redraw is queued rather than dropped.
- **No standing degrades to less, never to empty.**
  The rank cluster and stickers are simply not offered and the Standing template is withheld; the other recap cards still draw, minus their rank tab.

Anchors: `SavedClimbShareRankTests`, `ShareRecapBakeStateTests`, and `ShareStatClusterPickerEvidenceTests.aSavedClimbOpensWithoutItsRankAndGainsItWhenTheStandingLands`, which walks the saved path through the shipping view in a phone-sized window, from the rank-less card the captain reported to the standing landing behind the presented cover.
Keep that suite small on purpose: it is `.hostsAWindow`, which is the one test cost that can push `iOS Verify (Staging)` past its cap, and taking it from one test to four is what did (`ascend-deploy`).
New coverage belongs in the two cheap suites beside it unless it genuinely needs a live screen.

## Label placement and policy - the rule that keeps getting rewritten wrong
- **Where a label sits is a property of the element** (`ShareCardLabelPlacement`), not of the arrangement and not of which renderer ran. Changing the arrangement, or adding a metric, must leave it alone.
- **Whether a label appears at all is a property of the stat** (`ShareStatStickerKind.isSelfDescribing`, read through `ShareCardLabelPolicy`). A date, a name, a `#`-sigil rank speak for themselves; a bare number needs its unit. Never write that rule as an `if` inside a view - that is how `DATE` ended up under a date and how the climb-name exemption leaked.

## Stat sticker discipline (content-driven, mirrors the rest of the app)
- Stat stickers are typed, parameterized values - NOT per-stat bespoke layouts. A sticker is `(stat kind, label placement, arrangement, transform)`. Adding a new stat is data (a new kind + how to read it from the workout/climb), not a new code path.
- Stat values are read from the canonical `Workout` (and, for climbs, the attempt/leaderboard data) - never recomputed or stored on a share model. The composer reads derived values it trusts to be current.
- **Resolution never happens in the render path.** `ShareComposerViewModel` memoizes the resolver, the resolved stats, and each sticker's built card behind `@ObservationIgnored`, keyed on the content-bearing parts of the sticker only. A drag changes the transform, so it must not rebuild anything. Resolving splits filters the whole heart-rate series once per split; doing that inside `body` cost ~13 ms per frame (`ShareComposerGestureCostEvidenceTests`).
- Low-cardinality, privacy-safe: stickers display the same measured/derived metrics the rest of the app shows. No raw PII, no exact location.

## Stat clusters - pre-formatted groups, not a second sticker system

A **cluster** is a curated arrangement a climber drops on as one unit, so nobody has to lay stats out and nobody is pushed onto a recap card just to use their own photo.
It is an ordinary `ShareStickerInstance` carrying a `presetID`; the catalog is `Models/ShareStatClusterPreset.swift` and the tree is the same `ShareCardNode` format, drawn by the same interpreter.
Never grow a parallel model, renderer or gesture path for one.

**`docs/share-stat-clusters.md` owns the rules the clusters settled** (the plate-free default, one movable unit, availability from the data, the heart-rate labels, no wordmark inside a cluster, and the three faces they are designed in). Read it before editing the catalog; do not re-litigate those rules here.

- **Availability is computed, never declared per session type.** A preset declares `requires`; `ShareComposerViewModel.availablePresets()` offers it only when every one of those stats resolves. Never branch on `trackingMode` to decide what to show.
  Ask about the array a layout *draws*, not the stat behind it: `.splits` resolves off the pace timeline while the step-range table is built from a different array a short session leaves empty, which is why availability also reads `ShareStatClusterPreset.splitLayouts` (taken off the tree, so it cannot drift) and `ShareCardNode.resolves(in:)` branches on `ShareCardSplitsTableSpec.layout`.
  A number that describes the session is frozen into the session: the routine cluster's interval count is `HeadphoneMotionWorkoutMetadata.routineIntervalCount`, written at save time, never the live `Routine`'s - editing a routine must not rewrite a card the climber already shared.
- **Plate-free is a real branch, not a skipped modifier.** `ShareStickerCardBuilder.clusterNode` owns the wrap, so `.none` is a branch there; the edit rail's existing text-background control is the only thing that puts a panel behind a cluster.
- **Legibility is a property of the run, and it is size-dependent.** `ShareCardTextStyle.legibility` names the treatment (`none` / `shadow` / `outline`) and `ShareCardRenderer.shareCardTextLegibility` is the one place that decides what each costs. A large number survives a drop shadow; small tracked-out caps do not - against snow or a blown sky they lose their edges, so a run below `ShareStatClusterPresets.outlineBelow` also takes a hairline dark outline. That threshold is one constant: quote it, never restate the number.
  **The outline is four hard offset shadow copies, and the cost question is settled by measurement.** `Text` has no stroke, so the worry was that chained `.shadow`s nest rather than compose - five offscreen rasterizations per run on every frame of a drag. `theOutlineIsNotWhatMakesAClusterExpensiveToDraw` measures it: the Splits cluster, the heaviest thing a climber can place, draws in ~2.6 ms against the 8.3 ms 120 Hz budget at export scale (2.77×) in a 900×700 frame, and forcing every run's legibility to `.none` only reaches ~2.1 ms at that same size. That half-millisecond delta is the whole treatment - outline *and* contact shadows - not the outline alone, and even it is an upper bound because an `ImageRenderer` pass is a full layout plus rasterization where a drag re-composites an existing layer tree. Relocating the *identical* four-copy ring into a custom `TextRenderer` measured more expensive on a desk and level with the shipped spelling on a loaded CI runner, so what is asserted - and all that was ever worth asserting - is that the custom renderer buys nothing; that comparison is two spellings of the same ring, not a different technique.
  **Dragging is settled; the cost lives in layout.** With five clusters placed the composer's per-frame work is a memoized lookup, because `content(for:)` caches on the content-bearing parts of a sticker and a drag mutates only the transform - so "several clusters will stutter a drag" is disproved. That is protected by `ShareComposerViewModel.contentBuildCount`, which counts the cache-miss path: value equality on `ShareStickerContent` cannot see the cache being lost, since a rebuilt tree compares equal to a cached one. What costs is the one-off layout when a cluster is *placed*: `addTimeLayoutScalesLinearlyAsHeaviestClustersPileUp` measures add-time at the on-screen canvas (390×845) and at export (1080×2340) and asserts on a cluster's marginal cost over a background-only baseline, so the shared background cannot mask the scaling. Its current figures - on-screen, marginal over the background - are ~2.9 ms for one Splits cluster, ~8.3 ms for three and ~13.2 ms for five against an 8.3 ms 120 Hz frame, so **placing the third one already costs a full 120 Hz frame**. That is a one-off placement hitch and not a drag; recorded rather than fixed, tracked as issue #489.
  **Add-time is layout-bound, not rasterization-bound.** On-screen and export come back within a few percent of each other despite export being ~7.7× the pixels. A smaller canvas will not make it cheaper; the levers are the number of laid-out runs and caching a placed sticker. **Always write the canvas size next to a figure** anyway - an unlabelled millisecond is a number the next reader will misapply, the same discipline as the empty-context trap below. Be precise about what was never run: a genuinely single-pass stroked glyph (`AttributedString` negative `strokeWidth` + `strokeColor`) was specified and deliberately not measured, because ~0.5 ms - part of it contact shadows a stroke would not replace - is the ceiling on what it could win.
  **Measure a cluster through `presetPreview(for:)`, never against an empty `ShareCardRenderContext`.** With no resolved stats the split table and every stat-backed run draw nothing, so the timing is of a nearly empty tree. That mistake produced a 0.38 ms figure for the Splits cluster that briefly stood in this record; it is void, and ~2.6 ms is the real one. Anyone reopening the technique argues with that reasoning, not with a benchmark that does not exist. Two further traps, both paid for once already: widening the cluster's own shadow toward an ambient blur turns a stack of five split bars into a dark slab, and wrapping the treatment around a *row* rather than each `Text` does the same, because it draws four offset copies of a solid capsule. Judge any change to this on the brightest photo in the bundle (`OnboardingLandmarkEverestCard`, 16% of pixels above 0.75 luminance) and on a pure-white whiteout, never on an easy one.
- **The cluster owns its arrangement.** Label placement, the structure sheet and `toggleStat` do not apply - the rail hides them and the view model refuses them. Font and color still do.
- Sizes are the approved review page's own pixel values through `Design.u` (236pt mock -> 390pt design space), so that page stays the readable spec. **The page lives outside this repository**: it is `.lavish/ascend-stat-clusters.html` revision 6, alongside `data/ascend-summary-and-share-design.md`, both in the firstmate home - anyone with access can see the rendering, and anyone without it knows why they cannot find the file here. The sizes are self-checkable either way, because every one of them is the mock's own pixel value put through `Design.u`. A run that draws a landmark name needs a bounded `width` for `minimumScaleFactor` to shrink into, or a long tower drags the cluster past its own rule.
- Heart-rate copy is standardized in `ShareStatResolver` once, in the form `docs/share-stat-clusters.md` fixes; every sticker and cluster reads it from there rather than spelling its own.
- `ShareStatClusterPresetTests` and `ShareStatClusterPresetEvidenceTests` hold the rules a cluster cannot keep on its own, including that no cluster outgrows the add sheet's preview tile.

## What placing a cluster costs (measured, not re-derived)

Recorded here because the benchmark that produced it was deleted from CI on 2026-09-01: `addTimeLayoutScalesLinearlyAsHeaviestClustersPileUp` timed 108 `ImageRenderer` passes on every commit to answer a question that only changes when the feature does, and its 2,008 MB peak was the single largest memory consumer in the whole iOS suite (`ascend-deploy` has that story). Re-derive these by hand if the cluster renderer changes materially; do not put a timing assertion back on a shared runner.

Placing Splits, the heaviest cluster, on one canvas - median of 9 `ImageRenderer` passes each, export canvas 1080x2340:

| Clusters | Export-canvas layout |
|---|---|
| 0 (background only) | 0.56 ms |
| 1 | 2.93 ms |
| 3 | 6.77 ms |
| 5 | 10.49 ms |

- **Cost is linear in cluster count, not quadratic.** The first three clusters cost ~2.07 ms each; the fourth and fifth ~1.86 ms each. Piling clusters on does not cost dramatically more per cluster than starting the pile, which is the property that mattered.
- **This is layout and text shaping, not rasterization.** The on-screen 390x845 canvas and the export 1080x2340 one land within a few percent of each other despite ~7.7x the pixels, so a smaller canvas does not make it cheaper. Anyone attacking this should attack the number of laid-out runs or cache the placed sticker, never the resolution.
- **Every figure is a one-off first layout when a cluster is placed**, never a per-frame or drag cost, and every one is an upper bound: `ImageRenderer` lays out and rasterizes the whole canvas from scratch including the background, where the live app re-lays out a subtree over an already-realized one.
- **Add-time is over a 120 Hz frame from three clusters up.** That is a known one-off placement hitch rather than a drag cost, tracked as issue #489.
- The drag path is not timed and does not need to be: a transform-only mutation is a memoized lookup. `draggingPlacedClustersRebuildsNoCardTrees` still guards that on every commit - 120 frames of pan, pinch and rotate across five clusters must build zero card trees - because it is deterministic and allocates nothing. That half of the deleted benchmark was kept deliberately.

## Export pipeline
- **Photo background**: composite background + rendered sticker views into a single image (`ImageRenderer` for the stickers, drawn onto the background) -> save to Photos / share.
- **Video background**: the overlay is rendered once and burned onto every frame by Core Image, through `AVVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:)`, and written out by `AVAssetExportSession`. This is the hard, isolated piece - it only runs at export, and the editing UI is shared with the photo path.
- Export targets: Save to Photos and a dedicated Instagram Story share (`instagram-stories://` URL scheme) with a generic share-sheet fallback.
- **`ShareComposerExporter.exportSize` is the frame every source lands in, and it is not negotiable per source.** The canvas is `ShareCardFormat.aspectRatio` (9:19.5) fitted into whatever the chrome leaves, and the export writes 1080x2340 - one aspect, so a background composed on the canvas cannot be cropped or letterboxed by the export. The trap is that a video is the one source whose share is a movie rather than a still, so `renderImage` never runs for it: `exportVideo` built its composition from the *source video's* own frame and shipped a 9:16 clip the climber had already been shown cropped to fill 9:19.5. Any new export branch fills `exportSize` the way the canvas previews it (`resizeAspectFill`), **crops to that frame, and only then applies the climber's pinch and pan** - the canvas's own order, since the player layer clips the clip to the canvas bounds before SwiftUI scales and offsets the canvas-sized view. Fusing the fill and the pinch into one transform on the uncropped clip agrees only at the untouched fit: zoomed out or panned, the export shows footage the preview had already cropped away. `ShareComposerBackgroundFillEvidenceTests` exports every source and reads the pixels back - dimensions, bare-canvas bands, and the footage rectangle a zoomed and panned clip lands in - so a frame that reappears in one path fails there.

## Composer motion
Nothing on the canvas used to be animated. `ShareComposerAnimation` names the three curves - chrome around a drag, content reflow, sticker placement - and every canvas mutation goes through one of them. `withAnimation` lives in the view: `ShareComposerViewModel` does not import SwiftUI, so a mutation that should animate returns a fact (`handleDragEnded` returns whether it deleted) and the view decides.

## First-open walkthrough

The first composer open on an installation plays a four-step walkthrough - background sources, the stats sheet, the selected sticker's edit rail, filters - and never returns.
`ShareComposerWalkthroughCoordinator` owns the sequence, `ShareComposerWalkthroughStore` owns the single device-local key, and Debug Tools clears it.
**`docs/quality/contracts/issue-491.md` owns the step contract** (the ordering, the bounded wait for the picker's tabs, the fixed-length progress row, Skip and direct-entry behavior); read it before changing an order, a copy string, or what a step waits for.

- **It draws through the shared coach-mark component, never a composer-local one.** `CoachMarkOverlay` and `CoachMarkPresentation` render both this and the routine builder's marks - see `ascend-design-system`. The same "never a second renderer" discipline as the card format applies here.
- **A mark may only describe what is on screen.** The picker's tab pill and the sources card read one `ShareComposerSourceOptions`, and the edit-rail card is built from the selected sticker's own rail (`ShareComposerEditRailOptions`), so no card can name a control the climber does not have. A tab is offered only once something is behind it: no presets, no Presets tab; no resolved recap templates, no Recaps tab.
- **The walkthrough follows the composer; it never drives it.** Choosing a recap still skips the automatic stats-sheet stagger, so that journey waits for a manual Add Stats rather than opening the sheet just to have something to point at.

## Boundaries
- Photos library permission is requested at first share (point of use), never in onboarding.
  `NSPhotoLibraryUsageDescription` describes that one feature - photos and videos used as backgrounds for a shared climb - and is stored in four places that must be changed together (`ascend-privacy-manifest`).
- **`PHPhotoLibraryPreventAutomaticLimitedAccessAlert` is on, so the picker owns limited access itself.** iOS no longer re-prompts a limited-access climber on the first PhotoKit call after every launch; the in-context *Add more* control is the offer instead. That only works because `SharePhotoLibrary` registers a `PHPhotoLibraryChangeObserver` - the limited-library picker signals its result through exactly that callback, and it is also what makes a photo taken while the composer is open appear. Callbacks are coalesced and authorization is re-read on each one, because a climber can widen access from inside that sheet.
- Card templates ship **bundled**, and are rendered on-device. Do not build a remote template service or server-rendered card images. The format is shaped so a payload *could* later arrive over the wire; when a real reason appears (a campaign card, a template that ships broken), point the same decoder at the hosted climb-catalog channel this app already trusts (`HostedClimbCatalogRepository`) rather than adopting a second remote-content pattern. `minRendererVersion` filtering, unknown-element no-ops, and nullable stat references are already in place for that day.
- Backgrounds/presets are bundled or locally composed - NOT server-rendered. Don't reintroduce backend-driven share backgrounds or remote-configured stat layouts.
- The Live Climb completion summary stays as the emotional payoff; its Share button opens the composer (with the climb's card available as a background preset). The composer never replaces the summary screen itself.
- Legacy share card template assets may still live under `share-card-templates/...` in Storage, but workout share cards in v1 must not fetch their backgrounds or layout config from Firebase.
