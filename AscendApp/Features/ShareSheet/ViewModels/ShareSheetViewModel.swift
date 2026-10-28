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

    private let exporter: ShareSheetExporter
    private var toastTask: Task<Void, Never>?

    init(exporter: ShareSheetExporter = ShareSheetExporter()) {
        self.exporter = exporter
    }

    var shareExporter: ShareSheetExporter { exporter }

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

    func perform(_ action: CardAction, model: PresetCardModel, artwork: PresetCardArtwork) async {
        guard busyAction == nil else { return }
        busyAction = action
        defer { busyAction = nil }

        guard let card = exporter.renderCard(model: model, artwork: artwork) else {
            showToast("Couldn't render the card")
            return
        }

        switch action {
        case .story:
            let story = exporter.storyImage(from: card)
            if !exporter.shareToInstagramStory(story) {
                exporter.presentShareSheet(image: story)
            }
        case .copy:
            if exporter.copyToClipboard(card) {
                HapticsManager.shared.trigger(.lightImpact)
                showToast("Copied. Paste it in your story.")
            } else {
                showToast("Couldn't copy the card")
            }
        case .save:
            if await exporter.saveToPhotos(card) {
                HapticsManager.shared.trigger(.success)
                showToast("Saved to Photos")
            } else {
                showToast("Allow Photos access in Settings")
            }
        case .more:
            exporter.presentShareSheet(image: card)
        }
    }

    /// Copies a sticker's PNG to the clipboard.
    func copySticker(_ image: UIImage?) {
        guard let image, exporter.copyToClipboard(image) else {
            showToast("Couldn't copy the sticker")
            return
        }
        HapticsManager.shared.trigger(.lightImpact)
        showToast("Copied. Paste it in your story.")
    }

    /// Saves a sticker's PNG to Photos.
    func saveSticker(_ image: UIImage?) async {
        guard let image else {
            showToast("Couldn't save the sticker")
            return
        }
        if await exporter.saveToPhotos(image) {
            HapticsManager.shared.trigger(.success)
            showToast("Saved to Photos")
        } else {
            showToast("Allow Photos access in Settings")
        }
    }
}
