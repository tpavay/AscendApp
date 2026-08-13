import Foundation
import Observation

@MainActor
@Observable
final class ShareComposerWalkthroughCoordinator {
    enum BackgroundSelection: Equatable {
        case photoOrPreset
        case recap

        var automaticallyPresentsStatsSheet: Bool {
            self == .photoOrPreset
        }
    }

    enum Entry: Equatable {
        case picker
        case composer
    }

    enum State: Equatable {
        case waitingForSourceOptions
        case presenting(ShareComposerCoachMark)
        case waitingForBackground
        case waitingForStatsSheet
        case waitingForSticker
        case finished
    }

    /// How long the sources mark waits for the picker's real tabs. The picker itself is on screen
    /// from the first frame; only the mark holds, because a card that renamed its own sources
    /// after landing would be describing a screen the climber had already read.
    static let sourceOptionsResolutionLimit: Duration = .seconds(1)

    private(set) var state: State
    /// The control the mark that just left the screen was describing. VoiceOver lands there rather
    /// than at the top of the screen, and it clears the moment another mark takes over.
    private(set) var restingFocusTarget: ShareComposerCoachMarkTarget?
    let entry: Entry

    private let store: ShareComposerWalkthroughStore
    /// Seeded with the tabs known synchronously, replaced once the rest resolve, and frozen from
    /// the moment the sources mark presents.
    private var sourceOptions: ShareComposerSourceOptions
    private var editRailOptions: ShareComposerEditRailOptions = .full
    /// The marks this journey will actually show. The dot row counts these, so a step the climber
    /// never reaches is never a gap in the row.
    private var journeyMarks: [ShareComposerCoachMark]

    init(
        entry: Entry,
        sourceOptions: ShareComposerSourceOptions = .climb,
        store: ShareComposerWalkthroughStore = ShareComposerWalkthroughStore()
    ) {
        self.entry = entry
        self.sourceOptions = sourceOptions
        self.store = store
        journeyMarks = entry == .picker
            ? ShareComposerCoachMark.allCases
            : [.stats, .editRail, .filters]

        if store.hasSeenWalkthrough {
            state = .finished
        } else {
            state = entry == .picker ? .waitingForSourceOptions : .waitingForStatsSheet
        }
    }

    var mark: ShareComposerCoachMark? {
        guard case .presenting(let mark) = state else { return nil }
        return mark
    }

    var presentation: CoachMarkPresentation? {
        guard let mark, let index = journeyMarks.firstIndex(of: mark) else { return nil }
        return CoachMarkPresentation(
            title: mark.title(sourceOptions: sourceOptions),
            message: mark.message(sourceOptions: sourceOptions, editRailOptions: editRailOptions),
            stepCount: journeyMarks.count,
            stepIndex: index,
            primaryActionTitle: mark == .filters ? "Got it" : "Next",
            showsSkip: true
        )
    }

    var target: ShareComposerCoachMarkTarget? {
        mark.map(Self.target(for:))
    }

    /// The tabs the sources mark is describing, for as long as it is on screen. The picker draws
    /// its pill from this too, so the copy and the control it spotlights cannot disagree, and
    /// neither one can change under a card the climber is already reading.
    var presentedSourceOptions: ShareComposerSourceOptions? {
        mark == .sources ? sourceOptions : nil
    }

    /// The picker's real tabs arrived. The sources mark lands already naming them.
    func sourceOptionsResolved(_ options: ShareComposerSourceOptions) {
        guard state == .waitingForSourceOptions else { return }
        sourceOptions = options
        transition(to: .presenting(.sources))
    }

    /// The bounded wait ran out. Present naming only the tabs already known to be there, and
    /// never speak for a source that has not resolved.
    func sourceOptionsResolutionTimedOut() {
        guard state == .waitingForSourceOptions else { return }
        transition(to: .presenting(.sources))
    }

    func advance() {
        switch state {
        case .presenting(.sources):
            transition(to: .waitingForBackground)
        case .presenting(.stats):
            transition(to: .waitingForSticker)
        case .presenting(.editRail):
            transition(to: .presenting(.filters))
        case .presenting(.filters):
            finish()
        case .waitingForSourceOptions, .waitingForBackground, .waitingForStatsSheet,
             .waitingForSticker, .finished:
            break
        }
    }

    @discardableResult
    func backgroundSelected(_ selection: BackgroundSelection) -> Bool {
        if state == .waitingForBackground {
            transition(to: .waitingForStatsSheet)
        }
        return selection.automaticallyPresentsStatsSheet
    }

    func statsSheetPresented() {
        guard state == .waitingForStatsSheet else { return }
        transition(to: .presenting(.stats))
    }

    func statsSheetDismissed() {
        guard state == .presenting(.stats) else { return }
        transition(to: .waitingForStatsSheet)
    }

    /// Whatever the climber added, the walkthrough carries on: the edit step describes the rail the
    /// selected sticker actually offers, and a sticker with no rail at all drops that step from the
    /// journey and hands over to the filter mark rather than waiting for a control that will never
    /// appear.
    func stickerSelected(_ sticker: ShareStickerInstance?) {
        guard state == .waitingForSticker, let sticker else { return }

        guard let options = ShareComposerEditRailOptions(sticker: sticker) else {
            journeyMarks.removeAll { $0 == .editRail }
            transition(to: .presenting(.filters))
            return
        }
        editRailOptions = options
        transition(to: .presenting(.editRail))
    }

    func skip() {
        guard case .presenting = state else { return }
        finish()
    }

    static func target(for mark: ShareComposerCoachMark) -> ShareComposerCoachMarkTarget {
        switch mark {
        case .sources:
            return .sources
        case .stats:
            return .stats
        case .editRail:
            return .editRail
        case .filters:
            return .filters
        }
    }

    private func transition(to newState: State) {
        guard newState != state else { return }

        if case .presenting = newState {
            restingFocusTarget = nil
        } else if case .presenting(let leaving) = state {
            restingFocusTarget = Self.target(for: leaving)
        }
        state = newState
    }

    private func finish() {
        store.markSeen()
        transition(to: .finished)
    }
}
