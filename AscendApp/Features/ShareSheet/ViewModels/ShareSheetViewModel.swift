import Observation
import SwiftUI
import UIKit

/// The sheet's shell: which tab is showing, the toast, and the actions that send a card or a
/// sticker somewhere. The tabs own their own state.
@MainActor
@Observable
final class ShareSheetViewModel {
    enum Tab: Equatable {
        case presets
        case stickers
    }

    /// The four ways out of the Presets tab.
    enum CardAction {
        case story
        case copy
        case save
        case more
    }

    var tab: Tab = .presets
    private(set) var toast: String?
    private(set) var busyAction: CardAction?

    private let exporter: any ShareSheetExporting
    private let reporter: ShareSheetAnalyticsReporter
    private var toastTask: Task<Void, Never>?

    init(reporter: ShareSheetAnalyticsReporter, exporter: any ShareSheetExporting = ShareSheetExporter()) {
        self.reporter = reporter
        self.exporter = exporter
    }

    var shareExporter: any ShareSheetExporting { exporter }

    /// The toast shows for 1.7 seconds, then clears itself.
    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// A share is reported from the tap, whether or not the card then renders.
    func perform(_ action: CardAction, model: PresetCardModel, artwork: PresetCardArtwork) async {
        guard busyAction == nil else { return }
        busyAction = action
        defer { busyAction = nil }

        let shareAction = action.analyticsAction
        let content = ShareContent.card(layout: model.layout, background: ShareBackgroundKind(model.background))
        reporter.actionTapped(shareAction, content: content)

        guard let card = exporter.renderCard(model: model, artwork: artwork) else {
            showToast("Couldn't render the card")
            reporter.activityFinished(shareAction, content: content, outcome: .failed)
            return
        }

        switch action {
        case .story:
            if exporter.shareToInstagramStory(card) {
                reporter.activityFinished(shareAction, content: content, outcome: .completed)
            } else {
                presentSystemSheet(card, action: shareAction, content: content)
            }
        case .copy:
            if exporter.copyToClipboard(card) {
                HapticsManager.shared.trigger(.lightImpact)
                showToast("Copied. Paste it in your story.")
                reporter.activityFinished(shareAction, content: content, outcome: .completed)
            } else {
                showToast("Couldn't copy the card")
                reporter.activityFinished(shareAction, content: content, outcome: .failed)
            }
        case .save:
            if await exporter.saveToPhotos(card) {
                HapticsManager.shared.trigger(.success)
                showToast("Saved to Photos")
                reporter.activityFinished(shareAction, content: content, outcome: .completed)
            } else {
                showToast("Allow Photos access in Settings")
                reporter.activityFinished(shareAction, content: content, outcome: .failed)
            }
        case .more:
            presentSystemSheet(card, action: shareAction, content: content)
        }
    }

    /// Copies a sticker's PNG to the clipboard.
    func copySticker(_ image: UIImage?, content: ShareContent) {
        reporter.actionTapped(.copy, content: content)
        guard let image, exporter.copyToClipboard(image) else {
            showToast("Couldn't copy the sticker")
            reporter.activityFinished(.copy, content: content, outcome: .failed)
            return
        }
        HapticsManager.shared.trigger(.lightImpact)
        showToast("Copied. Paste it in your story.")
        reporter.activityFinished(.copy, content: content, outcome: .completed)
    }

    /// Saves a sticker's PNG to Photos.
    func saveSticker(_ image: UIImage?, content: ShareContent) async {
        reporter.actionTapped(.save, content: content)
        guard let image else {
            showToast("Couldn't save the sticker")
            reporter.activityFinished(.save, content: content, outcome: .failed)
            return
        }
        if await exporter.saveToPhotos(image) {
            HapticsManager.shared.trigger(.success)
            showToast("Saved to Photos")
            reporter.activityFinished(.save, content: content, outcome: .completed)
        } else {
            showToast("Allow Photos access in Settings")
            reporter.activityFinished(.save, content: content, outcome: .failed)
        }
    }

    // MARK: - Reporting

    /// The system sheet ends one of three ways, and only its own completion handler knows which:
    /// a destination was used, the climber cancelled, or there was no window to present on.
    private func presentSystemSheet(_ card: UIImage, action: ShareAction, content: ShareContent) {
        // The reporter, not self: the climber can dismiss the whole composer while the system
        // sheet is up, and that share still has to be reported.
        let reporter = reporter
        let presented = exporter.presentShareSheet(image: card) { activityType, completed in
            if completed {
                reporter.activityFinished(
                    action,
                    content: content,
                    outcome: .completed,
                    destination: ShareDestination(activityType: activityType)
                )
            } else {
                reporter.activityFinished(action, content: content, outcome: .cancelled, destination: ShareDestination.none)
            }
        }
        if !presented {
            reporter.activityFinished(action, content: content, outcome: .failed)
        }
    }
}

private extension ShareSheetViewModel.CardAction {
    var analyticsAction: ShareAction {
        switch self {
        case .story: return .story
        case .copy: return .copy
        case .save: return .save
        case .more: return .more
        }
    }
}
