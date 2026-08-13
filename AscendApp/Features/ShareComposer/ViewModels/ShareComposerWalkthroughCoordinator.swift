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
        case presenting(ShareComposerCoachMark)
        case waitingForBackground
        case waitingForStatsSheet
        case waitingForSticker
        case finished
    }

    private(set) var state: State
    /// The control the mark that just left the screen was describing. VoiceOver lands there rather
    /// than at the top of the screen, and it clears the moment another mark takes over.
    private(set) var restingFocusTarget: ShareComposerCoachMarkTarget?
    /// Which source tabs the picker is actually showing. Resolved content arrives after the first
    /// render, so the copy is updated rather than fixed at init.
    private(set) var sourceOptions: ShareComposerSourceOptions
    let entry: Entry

    private let store: ShareComposerWalkthroughStore
    private var editRailOptions: ShareComposerEditRailOptions = .full

    init(
        entry: Entry,
        sourceOptions: ShareComposerSourceOptions = .climb,
        store: ShareComposerWalkthroughStore = ShareComposerWalkthroughStore()
    ) {
        self.entry = entry
        self.sourceOptions = sourceOptions
        self.store = store

        if store.hasSeenWalkthrough {
            state = .finished
        } else {
            state = entry == .picker ? .presenting(.sources) : .waitingForStatsSheet
        }
    }

    var mark: ShareComposerCoachMark? {
        guard case .presenting(let mark) = state else { return nil }
        return mark
    }

    var presentation: CoachMarkPresentation? {
        guard let mark, let index = visibleMarks.firstIndex(of: mark) else { return nil }
        return CoachMarkPresentation(
            title: mark.title(sourceOptions: sourceOptions),
            message: mark.message(sourceOptions: sourceOptions, editRailOptions: editRailOptions),
            stepCount: visibleMarks.count,
            stepIndex: index,
            primaryActionTitle: mark == .filters ? "Got it" : "Next",
            showsSkip: true
        )
    }

    var target: ShareComposerCoachMarkTarget? {
        mark.map(Self.target(for:))
    }

    func updateSourceOptions(_ options: ShareComposerSourceOptions) {
        sourceOptions = options
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
        case .waitingForBackground, .waitingForStatsSheet, .waitingForSticker, .finished:
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
    /// selected sticker actually offers, and a sticker with no rail at all hands straight over to
    /// the filter mark rather than waiting for a control that will never appear.
    func stickerSelected(_ sticker: ShareStickerInstance?) {
        guard state == .waitingForSticker, let sticker else { return }

        guard let options = ShareComposerEditRailOptions(sticker: sticker) else {
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

    private var visibleMarks: [ShareComposerCoachMark] {
        switch entry {
        case .picker:
            return ShareComposerCoachMark.allCases
        case .composer:
            return [.stats, .editRail, .filters]
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
