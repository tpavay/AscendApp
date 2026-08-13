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
        case waitingForCompatibleSticker
        case finished
    }

    private(set) var state: State
    let entry: Entry

    private let store: ShareComposerWalkthroughStore
    private let sourceOptions: ShareComposerSourceOptions

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
            message: mark.message(sourceOptions: sourceOptions),
            stepCount: visibleMarks.count,
            stepIndex: index,
            primaryActionTitle: mark == .filters ? "Got it" : "Next",
            showsSkip: true
        )
    }

    var target: ShareComposerCoachMarkTarget? {
        switch mark {
        case .sources:
            return .sources
        case .stats:
            return .stats
        case .editRail:
            return .editRail
        case .filters:
            return .filters
        case nil:
            return nil
        }
    }

    func advance() {
        switch state {
        case .presenting(.sources):
            state = .waitingForBackground
        case .presenting(.stats):
            state = .waitingForCompatibleSticker
        case .presenting(.editRail):
            state = .presenting(.filters)
        case .presenting(.filters):
            finish()
        case .waitingForBackground, .waitingForStatsSheet, .waitingForCompatibleSticker, .finished:
            break
        }
    }

    @discardableResult
    func backgroundSelected(_ selection: BackgroundSelection) -> Bool {
        if state == .waitingForBackground {
            state = .waitingForStatsSheet
        }
        return selection.automaticallyPresentsStatsSheet
    }

    func statsSheetPresented() {
        guard state == .waitingForStatsSheet else { return }
        state = .presenting(.stats)
    }

    func statsSheetDismissed() {
        guard state == .presenting(.stats) else { return }
        state = .waitingForStatsSheet
    }

    func stickerSelected(_ sticker: ShareStickerInstance?) {
        guard state == .waitingForCompatibleSticker,
              let sticker,
              Self.isCompatibleWithFullEditRail(sticker) else { return }
        state = .presenting(.editRail)
    }

    func skip() {
        guard case .presenting = state else { return }
        finish()
    }

    static func isCompatibleWithFullEditRail(_ sticker: ShareStickerInstance) -> Bool {
        !sticker.isImage
            && !sticker.isPreset
            && !sticker.isStructured
            && sticker.kind.supportsComposite
    }

    private var visibleMarks: [ShareComposerCoachMark] {
        switch entry {
        case .picker:
            return ShareComposerCoachMark.allCases
        case .composer:
            return [.stats, .editRail, .filters]
        }
    }

    private func finish() {
        store.markSeen()
        state = .finished
    }
}
