---
name: ascend-share-composer
description: Use when working on Ascend sharing - the share composer canvas, backgrounds and presets, stat stickers, sticker gestures and snapping, photo and video export, AVFoundation compositing, Instagram Story sharing, or Photos permission at share time. Covers the user-composed canvas model that replaced fixed share-card carousels.
paths:
  - AscendApp/Features/ShareComposer/**
---

# Share Composer Architecture

Sharing in Ascend is a **user-composed canvas**, not a gallery of pre-designed cards. The user picks a background (their own photo/video or a preset), then drops stat "stickers" onto it and arranges them freely - the Instagram Story editor model. This replaces the older "carousel of fixed share-card variants" approach. Every share surface in the app (workout detail, Live Climb completion summary, manual log, Apple Health import) routes into the same composer.

## The two composable inputs - keep them independent
- **Background** = what fills the canvas. Sources: the user's Camera Roll (photo or video) or a bundled/known **preset**. For a Live Climb, the climb's bespoke share card becomes one of the presets - it's no longer a parallel share path. Backgrounds and stats are decoupled: a background is just a backing layer, never bundled with baked-in stats.
- **Stat stickers** = draggable overlays the user adds on top. Each sticker is one stat (Steps, Duration, Calories, Avg SPM, Heart Rate, Climb Rank/"Nth finisher", Climb Name, Date, etc.) rendered in a chosen visual style. The user adds as many as they want, in any arrangement.

## Composer interaction model
- Each sticker supports simultaneous pan / pinch-scale / rotate via composed SwiftUI gestures. Drag-to-bottom reveals a trash zone; release over it deletes the sticker.
- Alignment: center + edge snap guides (V1). Full Instagram-grade snapping (third-lines, between-sticker magnetism) is deferred.
- **Editing is SwiftUI-over-player; export is the only AVFoundation work.** While composing, the canvas is a SwiftUI `ZStack` of the background (an `Image` or an `AVPlayer`-backed video) with draggable sticker views on top - no composition happens during editing. Composition runs ONCE at save/share time.

## Stat sticker discipline (content-driven, mirrors the rest of the app)
- Stat stickers are typed, parameterized values - NOT per-stat bespoke layouts. A sticker is `(stat kind, visual style, transform)`. Adding a new stat is data (a new kind + how to read it from the workout/climb), not a new code path. Adding a new visual style is one reusable styled view that any stat can use.
- Stat values are read from the canonical `Workout` (and, for climbs, the attempt/leaderboard data) - never recomputed or stored on a share model. The composer reads derived values it trusts to be current.
- Low-cardinality, privacy-safe: stickers display the same measured/derived metrics the rest of the app shows. No raw PII, no exact location.

## Export pipeline
- **Photo background**: composite background + rendered sticker views into a single image (`ImageRenderer` for the stickers, drawn onto the background) -> save to Photos / share.
- **Video background**: burn the rendered sticker layers onto the video via `AVVideoCompositionCoreAnimationTool` + `AVAssetExportSession`. This is the hard, isolated piece - it only runs at export, and the editing UI is shared with the photo path. Build photo export first; video export slots in as a branch at the export step.
- Export targets: Save to Photos and a dedicated Instagram Story share (`instagram-stories://` URL scheme) with a generic share-sheet fallback.

## Boundaries
- Photos library permission is requested at first share (point of use), never in onboarding.
- Backgrounds/presets/sticker styles are bundled or locally composed - NOT server-rendered. Don't reintroduce backend-driven share backgrounds or remote-configured stat layouts.
- The Live Climb completion summary stays as the emotional payoff; its Share button opens the composer (with the climb's card available as a preset). The composer never replaces the summary screen itself.
- Legacy share card template assets may still live under `share-card-templates/...` in Storage, but workout share cards in v1 must not fetch their backgrounds or layout config from Firebase.
