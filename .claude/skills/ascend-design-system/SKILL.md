---
name: ascend-design-system
description: Use when building or reviewing Ascend UI conventions - branding and the Ascend wordmark, onboarding/auth screen chrome, sheets and AppSheetPreset, keyboard toolbars, level sliders, integrations cards, icons, climb card treatment, achievement motifs, or the spacing / corner-radius / animation-duration scales. Covers which shared component to reuse instead of rebuilding a screen-specific one.
paths:
  - AscendApp/Features/**
  - AscendApp/Shared/Components/**
  - AscendApp/Shared/Views/**
  - AscendApp/Shared/Managers/ThemeManager.swift
---

# Design System Conventions

Core tokens (fonts, accent, medal colors, theming) live in the core project guide. This skill holds the component conventions and scales.

Load the `swiftui-pro` skill for SwiftUI implementation review, and `product-design-playbook` for design/copy decisions.

## Component conventions
- **Icons**: SF Symbols (considering migrating to a custom icon set for consistency). For adding or syncing icon assets, use the `icon-workflow` skill.
- **Icon consistency**: Use the same icon for the same action across screens (for example, overflow menus should use one consistent `ellipsis` style app-wide unless product design explicitly says otherwise).
- **Level sliders**: Reuse the shared `SegmentedHeatmapSlider` for 1-25 heatmap-based level selection (base level onboarding and settings) instead of creating screen-specific segmented sliders. The routine builder is the one surface that does not use it - level there is set by dragging a timeline block, see `ascend-routines`.
- **Sheets**: Use `AppSheetPreset` with `.appSheetStyle(...)` for sheet sizing, drag indicator behavior, and sheet surface background instead of raw `presentationDetents` arrays at call sites. Use `AppSheetScaffold` for reusable sheet layouts, `AppSheetOptionRow` for menu-style options, and `appSheetButtonStyle(...)` for consistent sheet button semantics. Prefer a dedicated preset/layout pair for dense action sheets when they need tighter row density than general compact dialogs, and avoid root-level `Spacer()`-driven layouts in compact sheets.
- **Keyboard dismissal**: Reuse the shared `keyboardDoneToolbar(...)` helper with `KeyboardDismissButton` for text-entry keyboards that need an explicit Done action instead of re-creating keyboard toolbar buttons per screen.
- **Loading a single value**: Reuse the shared `AscendSkeletonText` / `AscendSkeletonCircle` (and `ascendSkeletonShimmer()`) from `Shared/Components/AscendSkeleton.swift` for a value that is genuinely in flight - label and layout stay put, only the value slot shimmers. Don't rebuild a per-screen shimmer, and don't park a status word ("Complete", "Checking") in a slot that holds a number; see `ascend-live-climbs` for why that reads as a load that never finished.
- **Integrations UI**: Keep integrations list cards as overview surfaces, not inline control panels. Shared card styling and structure should live under `Features/Integrations/Shared`, while provider-specific actions live in provider-owned manage sheets or detail surfaces.
- **Achievement motif vocabulary**: laurels represent personal achievements and record-book moments; crowns represent competitive ranking dominance. Do not combine laurel and crown in the same badge treatment.
- **Coach marks**: A spotlight-and-card walkthrough uses the shared `CoachMarkOverlay`, `CoachMarkPresentation`, and `coachMarkTarget(_:)` in `Shared/Components/CoachMarks/`. The routine builder and the share composer both render through it - a feature contributes its own targets and copy and nothing else. Don't rebuild the card, the dim, the spotlight ring, or the progress dots per screen; the routine names are typealiases onto the shared ones, not a second implementation.
- **Climb cards**: Reusable climb card surfaces share common chrome (split-card surface, leading artwork, animated tier border). Don't reimplement split layouts, image clipping, or tier-border animation per screen. See `ascend-live-climbs` for tier-border and Coming Soon treatment.

## Branding
- Use the angular Ascend `A` mark for in-app and launch-screen branding. The internal logo asset is `AppIconInternalAccent`; do not reintroduce the legacy stair-stepper logo for app branding surfaces.
- When displaying the word "Ascend" as part of app UI branding (top chrome, splash, onboarding, auth), use the integrated wordmark where the angular A mark serves as the letter A - not the A icon placed next to a separate "ASCEND" text label. The shared `AscendWordmark` component is the canonical implementation; reuse it rather than reinstating logo + text combos. The rule covers exported artwork too - a bundled share-card template never spells the brand as a literal `ASCEND` text run; `ShareCardTemplateView` draws the lockup itself in a fixed, protected band and a template chooses only its `wordmarkTint` (`docs/share-cards.md`) - and a surface that owns the whole lockup's color (a template asking for a dimmed or inverted brand) passes `markColor` so the angular A and the letters render as one tinted unit; leaving it nil keeps the mark's own brand color, which is what app chrome uses.
- The unauthenticated landing screen uses the bundled `OnboardingWelcomeBackground` asset with readability overlays. Keep a bundled image as the primary background - do not replace it with a generated gradient.
- Shared onboarding screens should use `OnboardingScaffold` for consistent top-left leading-control placement and bottom action layout. The control is a back chevron everywhere except the opening post-auth screen, which has nothing behind it and draws a sign-out glyph instead (`OnboardingLeadingControl`).
- The unauthenticated auth screen should stay background-first, using `AuthStaircaseBackground`, the angular Ascend `A` mark, Apple/Google provider buttons, and inline links to `https://ascendstepper.com/terms` and `https://ascendstepper.com/privacy`.

## Scales

These are established conventions, not hard rules - match the surrounding surface when it deliberately differs.

### Spacing
- Between sections: 24pt
- Between rows: 12pt
- Within elements: 8-12pt
- Component padding: 16pt (standard)
- Card padding: 20pt outer, 16pt inner

### Corner radius
- Cards/containers: 16pt
- Form fields: 12pt
- Badges: 6-8pt
- Buttons: 8-12pt

### Animation durations
- Content animations: `.easeInOut(duration: 0.2)`
- Theme transitions: `.easeInOut(duration: 0.3)`
- Transitions: `.opacity.combined(with: .move(edge:))`

### Theming opacity
- Text: `.white` / `.black` (100% primary)
- Secondary: `.white.opacity(0.6)` / `.gray`
- Tertiary: `.white.opacity(0.5)` / `.gray.opacity(0.7)`
- Backgrounds: `.white.opacity(0.05)` (dark) / `.gray.opacity(0.06)` (light)
- Borders: `.white.opacity(0.1)` (dark) / `.gray.opacity(0.15)` (light)

Resolve light/dark through `ThemeManager`'s `effectiveColorScheme` rather than reading `@Environment(\.colorScheme)` directly at the leaf.
