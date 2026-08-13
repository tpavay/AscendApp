# Feature Contract: Share composer first-open walkthrough

- Issue: #491
- Base branch: `develop`
- Change type: feature
- Owner: orchestrator

## User outcome

On the first share-composer open for an installation, a climber sees a four-step walkthrough that explains background sources, available stats, sticker editing, and whole-picture filters at the point where each control appears.
The walkthrough can be skipped from every step, does not return after completion or Skip, and can be replayed by clearing its device-local flag in Debug Tools.

## Non-goals

- Do not change any background, recap, stat cluster, sticker, filter, transform, or export behavior.
- Do not allow recap backgrounds to pan or zoom.
- Do not add a second coach-mark renderer, card, spotlight, dot row, or persistence mechanism.
- Do not address the add-time layout cost tracked in #489.
- Do not add timing or performance assertions.

## Acceptance criteria

- [ ] AC-1: A fresh installation sees source tabs, stats sheet, selected-sticker edit rail, and filter button marks in that order as it advances through the real picker-to-composer flow.
- [ ] AC-2: The source mark explains Camera Roll, Presets, and Recaps without promising recap transforms.
The picker itself is on screen from the first frame; only the mark waits, for at most one second, while recap availability resolves.
Whatever it lands naming is what it keeps naming, and the pill it spotlights draws from the same value, so neither the copy nor the tabs can change under a card the climber is already reading.
If the wait runs out, the mark names only the tabs already known to be there and says nothing about Recaps.
- [ ] AC-3: The stats mark truthfully explains available session stats and ready-made groups, including how an item is added and then moved, resized, or deleted.
- [ ] AC-4: The edit-rail mark explains the controls the selected sticker's own rail offers, naming arrangement and alignment only when that sticker shows them, and always naming font, color, and panel treatment.
Whatever the climber adds, the walkthrough carries on: a sticker with no rail at all hands straight over to the filters mark rather than waiting for a control that will never appear.
The dot row keeps one fixed length for the whole walkthrough on every path, and the current dot moves exactly one position between every displayed card.
A step this journey skips is visibly marked as passed rather than deleting a dot or leaving an indistinguishable pending dot.
- [ ] AC-5: The filters mark explains that filters affect the whole picture, that photo and preset backgrounds support drag and pinch, and that recap backgrounds remain fixed.
- [ ] AC-6: Skip from any of the four steps records the whole walkthrough as seen and dismisses it.
- [ ] AC-7: Completing the fourth step records the walkthrough as seen, and a second open presents no mark.
- [ ] AC-8: Entry directly at the composer starts a coherent composer-only sequence without attempting to present the missing picker mark.
- [ ] AC-9: Debug Tools clears the walkthrough's device-local seen flag.
- [ ] AC-10: The routine builder and share composer render through the same existing coach-mark presentation and overlay system.
- [ ] AC-11: Visual evidence includes one rendered image of each mark aligned to its real target.

## State matrix

| State | Expected behavior | Verification |
|---|---|---|
| Fresh picker entry | Draw the picker immediately and hold the source-tabs mark until its tabs resolve, then present with four-step progress. | Coordinator resolution test and picker evidence image. |
| Source tabs unresolved after one second | Present the mark naming only the tabs already known, and ignore a later resolution rather than rewrite it. | Coordinator timeout and frozen-set tests. |
| Picker mark advanced | Dismiss the mark and wait for a background choice before presenting a composer mark. | Coordinator transition test. |
| Composer reached from picker | Present the stats-sheet mark when the stats sheet is available. | Coordinator test and stats-sheet evidence image. |
| Any sticker with an edit rail selected | Present the edit-rail mark describing that rail's own controls. | Parameterized coordinator test and edit-rail evidence image. |
| Sticker with no edit rail selected | Drop the edit step from the displayed journey and present the filters mark in its place, keeping the row at four dots, advancing the current dot by one, and rendering the unused position as passed. | Coordinator dot-row test. |
| Background chosen while the source tabs are still resolving | Drop the sources mark from the journey and carry on at the stats step, rather than presenting it over the composer. | Coordinator state-machine test. |
| Edit-rail mark advanced | Present the filters mark. | Coordinator order test and filters evidence image. |
| Direct composer entry | Start at stats with three coherent progress steps. | Coordinator direct-entry test; no production route constructs it, see Risk and rollout. |
| Skip from any mark | Persist seen state and dismiss all pending marks. | Parameterized Skip test across all steps. |
| Completed or skipped installation | Present no walkthrough on any later open. | Second-open test. |
| Recap background | Allow stickers but refuse background pan and zoom. | Existing view-model tests plus walkthrough copy test. |
| Debug replay | Remove the device-local seen value so the next open starts again. | Debug action test or direct storage-key assertion. |
| Loading recap | Do not place a coach mark over the recap rendering progress state. | Inspection and coordinator location gating. |
| Error/offline | Walkthrough remains local and does not depend on connectivity. | Unit test uses isolated local defaults with no network. |

## Test mapping

| Acceptance criterion | Automated test or evidence | Why it proves the behavior |
|---|---|---|
| AC-1 | Ordered coordinator transition test plus four evidence renders. | Verifies the state order and each target's rendered placement. |
| AC-2 | Exact presentation-copy test, plus the hold, timeout, and frozen-set coordinator tests. | Prevents source descriptions from drifting, inventing behavior, or rewriting themselves after the card has landed. |
| AC-3 | Exact presentation-copy test and add-sheet host evidence. | Keeps the instruction aligned to tap-to-add and existing sticker gestures. |
| AC-4 | Parameterized per-sticker copy and state test, plus the no-rail hand-off test. | Ensures each claim appears only where the rail offers that control, and that no addition can strand the walkthrough. |
| AC-5 | Exact presentation-copy test plus existing transform support assertions. | Preserves the photo/preset versus recap transform boundary. |
| AC-6 | Parameterized Skip test for all four steps. | Proves every Skip path records seen state and clears pending work. |
| AC-7 | Completion and second-open tests. | Proves the once-per-install contract. |
| AC-8 | Direct-entry coordinator test. | Proves the missing picker step is excluded from progress and targeting. |
| AC-9 | Debug action test or storage-key assertion. | Proves Debug Tools resets the exact key the coordinator reads. |
| AC-10 | Shared-overlay compilation and anchor-resolution tests. | Proves both hosts use one implementation. |
| AC-11 | Four PNG evidence files. | Shows the spotlight and card in place for every mark. |

## UX evidence

- Capture the source-tabs mark on the background picker in dark appearance.
- Capture the stats mark with the real stats sheet visible in dark appearance.
- Capture the edit-rail mark with a compatible stat sticker selected in dark appearance.
- Capture the filters mark on the composer canvas in dark appearance.
- Use a task-owned iPhone simulator and target only that device.
- Inspect the four images for spotlight alignment, readable card copy, safe-area clearance, and 44-point controls.
- Verify the modal overlay exposes Skip and its primary action to VoiceOver and supports the accessibility escape action.
- Verify coach-mark chrome scales with Dynamic Type without changing exported card content.

## Risk and rollout

No data migration, backend contract, network, privacy declaration, authentication, payment, or deployment-order change is involved.
The only persisted value is a device-local walkthrough seen flag equivalent to the routine builder's existing flag.
The change is backward compatible because every share entry point retains its picker-first behavior, including the stagger before the stats sheet auto-presents.

A `ShareComposerView(initialBackground:)` parameter was drafted so the composer could be opened with a background already chosen, and it was removed during firstmate's review of this branch.
Both production entry points, `WorkoutDetailView` and `LiveClimbCompletionSummaryView`, construct the composer without it, so nothing but a test could reach it: it was production API whose only caller was the test suite.
The composer-only sequence it existed to demonstrate is now covered directly against `ShareComposerWalkthroughCoordinator` through `Entry.composer`, which keeps the behavior specified and tested without shipping an unreachable seam.
If a direct-entry share surface is added later, that entry is already modeled and only needs a host.
No analytics event or new screen route is introduced.
No feature flag is required because the new write is disposable presentation state rather than user-authored or server-synced product data, and Debug Tools can clear it.
Rollback removes the presentation coordinator and host modifiers without affecting share content.

## Human gates

- None.
