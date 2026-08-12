---
name: ascend-share-composer
description: Use when working on Ascend sharing - the share composer canvas, the declarative share-card format and its one interpreter, card templates and their bundled JSON, backgrounds and presets, stat stickers and label placement, sticker gestures and snapping, photo and video export, AVFoundation compositing, Instagram Story sharing, or Photos permission at share time. Covers the user-composed canvas model that replaced fixed share-card carousels.
paths:
  - AscendApp/Features/ShareComposer/**
  - scripts/validate-share-card-templates.mjs
  - scripts/test/share-card-templates.test.mjs
---

# Share Composer Architecture

Sharing in Ascend is a **user-composed canvas**, not a gallery of pre-designed cards. The user picks a background (their own photo/video or a preset), then drops stat "stickers" onto it and arranges them freely - the Instagram Story editor model. This replaces the older "carousel of fixed share-card variants" approach. Every share surface in the app (workout detail, Live Climb completion summary) routes into the same composer.

## The two composable inputs - keep them independent
- **Background** = what fills the canvas. Sources: the user's Camera Roll (photo or video) or a bundled/known **preset**. For a Live Climb, the climb's bespoke share card becomes one of the presets - it's no longer a parallel share path. Backgrounds and stats are decoupled: a background is just a backing layer, never bundled with baked-in stats.
- **Stat stickers** = draggable overlays the user adds on top. A sticker carries one stat (Steps, Duration, Calories, Avg SPM, Heart Rate, Climb Rank/"Nth finisher", Climb Name, Date, etc.), optionally composited with more, and is drawn by the card format - see *One card format, one interpreter*. The user adds as many as they want, in any arrangement.

## Composer interaction model
- Each sticker supports simultaneous pan / pinch-scale / rotate via composed SwiftUI gestures. Drag-to-bottom reveals a trash zone; release over it deletes the sticker.
- Alignment: center + edge snap guides (V1). Full Instagram-grade snapping (third-lines, between-sticker magnetism) is deferred.
- **Editing is SwiftUI-over-player; export is the only AVFoundation work.** While composing, the canvas is a SwiftUI `ZStack` of the background (an `Image` or an `AVPlayer`-backed video) with draggable sticker views on top - no composition happens during editing. Composition runs ONCE at save/share time.

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

- **Availability follows the data, never the session type.** A preset declares `requires`; `ShareComposerViewModel.availablePresets()` offers it only when every one of those stats resolves. That single rule is why one catalog serves a Live Climb, a routine and a Just Climb - do not branch on `trackingMode` to decide what to show.
- **Plate-free by default.** A cluster ships with no backing panel and stays legible on its shadow alone; the edit rail's existing text-background control is still the only way a panel appears. `ShareStickerCardBuilder.clusterNode` owns that, so `.none` is a real branch there rather than a no-op.
- **The cluster owns its arrangement.** Label placement, the structure sheet and `toggleStat` do not apply - the rail hides them and the view model refuses them. Font and color still do.
- Sizes are the approved review page's own pixel values through `Design.u` (236pt mock -> 390pt design space), so the page stays the readable spec. A run that draws a landmark name needs a bounded `width` for `minimumScaleFactor` to shrink into, or a long tower drags the cluster past its own rule.
- Heart-rate copy is standardized in `ShareStatResolver` once: **AVERAGE HR** and **MAX HR**, no BPM suffix and no glyph. Every sticker and cluster reads it from there.
- `ShareStatClusterPresetTests` and `ShareStatClusterPresetEvidenceTests` hold the rules a cluster cannot keep on its own, including that no cluster outgrows the add sheet's preview tile.

## Export pipeline
- **Photo background**: composite background + rendered sticker views into a single image (`ImageRenderer` for the stickers, drawn onto the background) -> save to Photos / share.
- **Video background**: burn the rendered sticker layers onto the video via `AVVideoCompositionCoreAnimationTool` + `AVAssetExportSession`. This is the hard, isolated piece - it only runs at export, and the editing UI is shared with the photo path. Build photo export first; video export slots in as a branch at the export step.
- Export targets: Save to Photos and a dedicated Instagram Story share (`instagram-stories://` URL scheme) with a generic share-sheet fallback.

## Composer motion
Nothing on the canvas used to be animated. `ShareComposerAnimation` names the three curves - chrome around a drag, content reflow, sticker placement - and every canvas mutation goes through one of them. `withAnimation` lives in the view: `ShareComposerViewModel` does not import SwiftUI, so a mutation that should animate returns a fact (`handleDragEnded` returns whether it deleted) and the view decides.

## Boundaries
- Photos library permission is requested at first share (point of use), never in onboarding.
- Card templates ship **bundled**, and are rendered on-device. Do not build a remote template service or server-rendered card images. The format is shaped so a payload *could* later arrive over the wire; when a real reason appears (a campaign card, a template that ships broken), point the same decoder at the hosted climb-catalog channel this app already trusts (`HostedClimbCatalogRepository`) rather than adopting a second remote-content pattern. `minRendererVersion` filtering, unknown-element no-ops, and nullable stat references are already in place for that day.
- Backgrounds/presets are bundled or locally composed - NOT server-rendered. Don't reintroduce backend-driven share backgrounds or remote-configured stat layouts.
- The Live Climb completion summary stays as the emotional payoff; its Share button opens the composer (with the climb's card available as a preset). The composer never replaces the summary screen itself.
- Legacy share card template assets may still live under `share-card-templates/...` in Storage, but workout share cards in v1 must not fetch their backgrounds or layout config from Firebase.
