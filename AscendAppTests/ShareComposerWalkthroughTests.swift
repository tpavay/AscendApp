import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
struct ShareComposerWalkthroughTests {
    @Test(.bug(id: 491))
    func pickerEntryAdvancesThroughFourRealTargetsInOrder() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = pickerCoordinator(fixture)

        verify(coordinator, mark: .sources, target: .sources, step: 0, count: 4)

        coordinator.advance()
        #expect(coordinator.state == .waitingForBackground)
        #expect(coordinator.mark == nil)

        #expect(coordinator.backgroundSelected(.photoOrPreset))
        #expect(coordinator.state == .waitingForStatsSheet)
        #expect(coordinator.mark == nil)

        coordinator.statsSheetPresented()
        verify(coordinator, mark: .stats, target: .stats, step: 1, count: 4)

        coordinator.advance()
        #expect(coordinator.state == .waitingForSticker)

        coordinator.stickerSelected(ShareStickerInstance(kind: .duration))
        verify(coordinator, mark: .editRail, target: .editRail, step: 2, count: 4)

        coordinator.advance()
        verify(coordinator, mark: .filters, target: .filters, step: 3, count: 4)

        coordinator.advance()
        #expect(coordinator.state == .finished)
        #expect(fixture.store.hasSeenWalkthrough)
    }

    @Test(arguments: ShareComposerCoachMark.allCases)
    func skipFromEveryMarkRecordsTheWholeWalkthroughAsSeen(_ mark: ShareComposerCoachMark) {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = pickerCoordinator(fixture)

        drive(coordinator, to: mark)
        #expect(coordinator.mark == mark)

        coordinator.skip()

        #expect(coordinator.state == .finished)
        #expect(coordinator.mark == nil)
        #expect(fixture.store.hasSeenWalkthrough)
    }

    @Test
    func completingTheWalkthroughPreventsASecondOpen() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let first = pickerCoordinator(fixture)

        drive(first, to: .filters)
        first.advance()

        let second = ShareComposerWalkthroughCoordinator(entry: .picker, store: fixture.store)
        #expect(second.state == .finished)
        #expect(second.mark == nil)
        #expect(second.presentation == nil)
    }

    @Test
    func directComposerEntryStartsAtStatsWithThreeCoherentSteps() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = ShareComposerWalkthroughCoordinator(entry: .composer, store: fixture.store)

        #expect(coordinator.state == .waitingForStatsSheet)
        #expect(coordinator.mark == nil)

        coordinator.statsSheetPresented()
        verify(coordinator, mark: .stats, target: .stats, step: 0, count: 3)

        coordinator.advance()
        coordinator.stickerSelected(ShareStickerInstance(kind: .steps))
        verify(coordinator, mark: .editRail, target: .editRail, step: 1, count: 3)

        coordinator.advance()
        verify(coordinator, mark: .filters, target: .filters, step: 2, count: 3)
    }

    @Test(.bug(id: 491), arguments: StickerUnderTest.allCases)
    func everyStickerWithARailReachesTheEditMarkDescribingOnlyItsOwnControls(
        _ subject: StickerUnderTest
    ) throws {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = pickerCoordinator(fixture)
        drive(coordinator, to: .stats)
        coordinator.advance()

        coordinator.stickerSelected(subject.sticker)

        verify(coordinator, mark: .editRail, target: .editRail, step: 2, count: 4)
        #expect(try #require(coordinator.presentation).message == subject.expectedMessage)

        coordinator.advance()
        verify(coordinator, mark: .filters, target: .filters, step: 3, count: 4)
        coordinator.advance()
        #expect(coordinator.state == .finished)
        #expect(fixture.store.hasSeenWalkthrough)
    }

    /// The dropped edit step leaves no gap in the dot row: the journey is three marks long and the
    /// filter mark is its third, not a fourth with an unfilled dot behind it.
    @Test(.bug(id: 491))
    func aStickerWithNoEditRailHandsStraightOverToTheFilterMarkWithoutSkippingADot() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = pickerCoordinator(fixture)
        drive(coordinator, to: .stats)
        coordinator.advance()

        coordinator.stickerSelected(ShareStickerInstance(kind: .climbName, climbImageVariant: .thumb))

        verify(coordinator, mark: .filters, target: .filters, step: 2, count: 3)

        coordinator.advance()
        #expect(coordinator.state == .finished)
        #expect(fixture.store.hasSeenWalkthrough)
    }

    @Test(.bug(id: 491))
    func aSecondOpenStaysSilentAfterAReadyMadeGroupCompletedTheFirst() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let first = pickerCoordinator(fixture)
        drive(first, to: .stats)
        first.advance()
        first.stickerSelected(StickerUnderTest.readyMadeGroup.sticker)
        first.advance()
        first.advance()

        let second = ShareComposerWalkthroughCoordinator(entry: .picker, store: fixture.store)
        #expect(second.state == .finished)
        #expect(second.presentation == nil)
    }

    @Test(.bug(id: 491))
    func eachDismissedMarkLeavesFocusOnTheControlItExplained() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = pickerCoordinator(fixture)
        #expect(coordinator.restingFocusTarget == nil)

        coordinator.advance()
        #expect(coordinator.restingFocusTarget == .sources)

        coordinator.backgroundSelected(.photoOrPreset)
        coordinator.statsSheetPresented()
        #expect(coordinator.restingFocusTarget == nil)

        coordinator.advance()
        #expect(coordinator.restingFocusTarget == .stats)

        coordinator.stickerSelected(ShareStickerInstance(kind: .duration))
        #expect(coordinator.restingFocusTarget == nil)

        coordinator.skip()
        #expect(coordinator.restingFocusTarget == .editRail)
    }

    @Test(.bug(id: 491))
    func theFilterMarkLeavesFocusOnTheFilterControl() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = pickerCoordinator(fixture)
        drive(coordinator, to: .filters)

        coordinator.advance()

        #expect(coordinator.state == .finished)
        #expect(coordinator.restingFocusTarget == .filters)
    }

    @Test(.bug(id: 491))
    func theSourceMarkHoldsUntilItsTabsResolveAndThenLandsAlreadyCorrect() throws {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = ShareComposerWalkthroughCoordinator(
            entry: .picker,
            sourceOptions: ShareComposerSourceOptions(hasPresets: true, hasRecaps: false),
            store: fixture.store
        )

        #expect(coordinator.state == .waitingForSourceOptions)
        #expect(coordinator.mark == nil)
        #expect(coordinator.presentation == nil)
        #expect(coordinator.presentedSourceOptions == nil)

        coordinator.sourceOptionsResolved(
            ShareComposerSourceOptions(hasPresets: true, hasRecaps: true)
        )

        let presentation = try #require(coordinator.presentation)
        #expect(presentation.title == "Three ways to start.")
        #expect(presentation.message.localizedStandardContains("Recaps"))
        #expect(coordinator.presentedSourceOptions?.hasRecaps == true)
    }

    /// The wait is bounded, and what lands after it stays landed: a late resolution must not
    /// rewrite a card the climber is already reading, nor grow the pill it is spotlighting.
    @Test(.bug(id: 491))
    func aTimedOutSourceMarkNamesOnlyKnownTabsAndIsNeverRewritten() throws {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = ShareComposerWalkthroughCoordinator(
            entry: .picker,
            sourceOptions: ShareComposerSourceOptions(hasPresets: true, hasRecaps: false),
            store: fixture.store
        )

        coordinator.sourceOptionsResolutionTimedOut()

        let landed = try #require(coordinator.presentation)
        #expect(landed.title == "Two ways to start.")
        #expect(landed.message.localizedStandardContains("Recaps") == false)
        #expect(coordinator.presentedSourceOptions?.hasRecaps == false)

        coordinator.sourceOptionsResolved(
            ShareComposerSourceOptions(hasPresets: true, hasRecaps: true)
        )

        #expect(try #require(coordinator.presentation).title == landed.title)
        #expect(try #require(coordinator.presentation).message == landed.message)
        #expect(coordinator.presentedSourceOptions?.hasRecaps == false)
    }

    /// Once the mark is gone the picker is free to draw whatever has since resolved, so a frozen
    /// set never outlives the card that froze it.
    @Test(.bug(id: 491))
    func theFrozenSourceSetIsReleasedWhenTheMarkLeaves() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = ShareComposerWalkthroughCoordinator(
            entry: .picker,
            sourceOptions: ShareComposerSourceOptions(hasPresets: true, hasRecaps: false),
            store: fixture.store
        )
        coordinator.sourceOptionsResolutionTimedOut()
        #expect(coordinator.presentedSourceOptions != nil)

        coordinator.advance()

        #expect(coordinator.presentedSourceOptions == nil)
    }

    @Test
    func presentationCopyStatesTheShippedContentAndInteractionFactsExactly() {
        #expect(
            ShareComposerCoachMark.sources.message
                == "Camera Roll is your own photos. Presets are Ascend climb artwork. Recaps are ready-made cards with the stats already laid out."
        )
        #expect(
            ShareComposerCoachMark.stats.message
                == "Tap any available session stat or a ready-made group to add it. Then move or resize the sticker, or drag it to the trash to delete it."
        )
        #expect(
            ShareComposerCoachMark.editRail.message
                == "Change the arrangement, alignment, font, and color. Add a panel when the picture is busy."
        )
        #expect(
            ShareComposerCoachMark.filters.message
                == "Filters change the whole picture. Drag and pinch your photo or a preset background. Recaps stay fixed."
        )

        #expect(ShareComposerCoachMark.stats.message.localizedStandardContains("tap"))
        #expect(ShareComposerCoachMark.stats.message.localizedStandardContains("drag one on") == false)
        #expect(ShareComposerCoachMark.sources.message.localizedStandardContains("recap") == true)
        #expect(ShareComposerCoachMark.sources.message.localizedStandardContains("pinch") == false)
    }

    @Test
    func nonClimbPickerDescribesOnlyItsAvailableCameraRollSource() throws {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = ShareComposerWalkthroughCoordinator(
            entry: .picker,
            sourceOptions: .cameraRollOnly,
            store: fixture.store
        )
        coordinator.sourceOptionsResolved(.cameraRollOnly)
        let presentation = try #require(coordinator.presentation)

        #expect(presentation.title == "Start with Camera Roll.")
        #expect(presentation.message == "Camera Roll is your own photos.")
        #expect(presentation.message.localizedStandardContains("Presets") == false)
        #expect(presentation.message.localizedStandardContains("Recaps") == false)
    }

    @Test
    func pickerRecapWaitsForManualStatsSheetWithoutDanglingPresentation() {
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        let coordinator = pickerCoordinator(fixture)

        coordinator.advance()
        #expect(coordinator.backgroundSelected(.recap) == false)

        #expect(coordinator.state == .waitingForStatsSheet)
        #expect(coordinator.mark == nil)
        #expect(coordinator.presentation == nil)

        coordinator.statsSheetPresented()
        verify(coordinator, mark: .stats, target: .stats, step: 1, count: 4)

        coordinator.statsSheetDismissed()
        #expect(coordinator.state == .waitingForStatsSheet)
        #expect(coordinator.presentation == nil)
    }

    /// Driven through the action the Debug Tools list actually publishes, so the routing the
    /// screen relies on is exercised rather than the reset helper alone.
    @Test
    func debugResetRemovesTheExactKeyReadByTheCoordinator() async throws {
        #if DEBUG
        let fixture = DefaultsFixture()
        defer { fixture.cleanUp() }
        fixture.store.markSeen()
        #expect(fixture.defaults.bool(forKey: ShareComposerCoachMark.seenStorageKey))

        let debugTools = DebugToolsViewModel(shareComposerWalkthroughStore: fixture.store)
        let action = try #require(
            debugTools.sections
                .flatMap(\.actions)
                .first { $0.title == "Reset Share Composer Walkthrough" },
            "Debug Tools no longer publishes the Share Composer walkthrough reset"
        )
        let container = try ModelContainer(
            for: Workout.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        await debugTools.executeAction(
            action,
            modelContext: ModelContext(container),
            authVM: AuthenticationViewModel(observesFirebaseAuth: false)
        )

        #expect(fixture.defaults.object(forKey: ShareComposerCoachMark.seenStorageKey) == nil)
        let replay = pickerCoordinator(fixture)
        #expect(replay.mark == .sources)
        #expect(debugTools.successMessage == "Share Composer walkthrough will play again on this device.")
        #endif
    }

    @Test
    func statsSpotlightUsesTheVisibleBottomOfScrollableSheetContent() {
        let rect = ShareComposerCoachMarkGeometry.statsSpotlightRect(
            for: CGRect(x: 0, y: 80, width: 390, height: 900),
            in: CGSize(width: 390, height: 500)
        )

        #expect(rect == CGRect(x: 8, y: 345, width: 374, height: 150))
    }

    /// A picker coordinator whose source tabs have already resolved, which is where every journey
    /// through the marks starts.
    private func pickerCoordinator(
        _ fixture: DefaultsFixture,
        sourceOptions: ShareComposerSourceOptions = .climb
    ) -> ShareComposerWalkthroughCoordinator {
        let coordinator = ShareComposerWalkthroughCoordinator(entry: .picker, store: fixture.store)
        coordinator.sourceOptionsResolved(sourceOptions)
        return coordinator
    }

    private func drive(
        _ coordinator: ShareComposerWalkthroughCoordinator,
        to mark: ShareComposerCoachMark
    ) {
        guard mark != .sources else { return }
        coordinator.advance()
        coordinator.backgroundSelected(.photoOrPreset)
        coordinator.statsSheetPresented()
        guard mark != .stats else { return }
        coordinator.advance()
        coordinator.stickerSelected(ShareStickerInstance(kind: .duration))
        guard mark != .editRail else { return }
        coordinator.advance()
    }

    private func verify(
        _ coordinator: ShareComposerWalkthroughCoordinator,
        mark: ShareComposerCoachMark,
        target: ShareComposerCoachMarkTarget,
        step: Int,
        count: Int
    ) {
        #expect(coordinator.mark == mark)
        #expect(coordinator.target == target)
        #expect(coordinator.presentation?.stepIndex == step)
        #expect(coordinator.presentation?.stepCount == count)
        #expect(coordinator.presentation?.showsSkip == true)
    }
}

/// The three shapes the edit rail draws differently: a plain metric offers every control, while a
/// structured sticker and a curated cluster own their own arrangement and offer neither.
enum StickerUnderTest: CaseIterable {
    case singleMetric
    case structured
    case readyMadeGroup

    var sticker: ShareStickerInstance {
        switch self {
        case .singleMetric:
            return ShareStickerInstance(kind: .duration)
        case .structured:
            return ShareStickerInstance(kind: .splits)
        case .readyMadeGroup:
            return ShareStickerInstance(
                kind: .steps,
                presetID: ShareStatClusterPresets.all.first?.id
            )
        }
    }

    var expectedMessage: String {
        switch self {
        case .singleMetric:
            return "Change the arrangement, alignment, font, and color. Add a panel when the picture is busy."
        case .structured, .readyMadeGroup:
            return "Change the font and color. Add a panel when the picture is busy."
        }
    }
}

private final class DefaultsFixture {
    let suiteName = "ShareComposerWalkthroughTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let store: ShareComposerWalkthroughStore

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = ShareComposerWalkthroughStore(defaults: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
