import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Renders a card or sticker to an image and routes it to the clipboard, Photos, Instagram Stories
/// or the system share sheet.
@MainActor
struct ShareSheetExporter {
    /// A card is exported square at 1080 points, the size the design specifies.
    static let cardExportSize: CGFloat = 1080
    /// Instagram's pasteboard key for an image placed over the Story as a movable sticker. The card
    /// goes here, never under `backgroundImage`, so Instagram draws only the rounded square and
    /// the transparent corners stay transparent.
    static let instagramStickerKey = "com.instagram.sharedSticker.stickerImage"
    /// A sticker is drawn at 3x so it stays crisp when pasted at any size.
    static let stickerScale: CGFloat = 3

    private let climbImageRepository: any ClimbImageRepository

    init(climbImageRepository: any ClimbImageRepository = FirebaseClimbImageRepository.shared) {
        self.climbImageRepository = climbImageRepository
    }

    // MARK: - Rendering

    /// The card at export size. The corners are transparent, as the card is rounded.
    func renderCard(model: PresetCardModel, artwork: PresetCardArtwork) -> UIImage? {
        let renderer = ImageRenderer(
            content: PresetCardCanvas(model: model, artwork: artwork, size: Self.cardExportSize)
        )
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// A sticker at 3x on a transparent background.
    func renderSticker<Content: View>(_ content: Content) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = Self.stickerScale
        renderer.isOpaque = false
        return renderer.uiImage
    }

    func loadClimbArtwork(for climb: Climb) async -> UIImage? {
        await ClimbArtworkView.loadImage(for: climb, variant: .hero, imageRepository: climbImageRepository)
    }

    // MARK: - Clipboard

    /// Puts the PNG on the clipboard as `public.png` data so a paste keeps its transparency.
    @discardableResult
    func copyToClipboard(_ image: UIImage) -> Bool {
        guard let data = image.pngData() else { return false }
        UIPasteboard.general.setItems([[UTType.png.identifier: data]])
        return true
    }

    // MARK: - Photos

    private struct UncheckedData: @unchecked Sendable { let data: Data }

    /// Saves a PNG to Photos with add-only permission, keeping its transparency.
    func saveToPhotos(_ image: UIImage) async -> Bool {
        guard let data = image.pngData() else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await Self.write(UncheckedData(data: data))
    }

    /// `PHPhotoLibrary` runs the change block on its own queue; a change block built inside a
    /// `@MainActor` type is inferred main-actor isolated and trips `dispatch_assert_queue`
    /// (Apple DTS forum 763665), so the write lives in a `nonisolated` helper.
    nonisolated private static func write(_ boxed: UncheckedData) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.png.identifier
                request.addResource(with: .photo, data: boxed.data, options: options)
                request.creationDate = Date()
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Instagram Stories and the share sheet

    /// The pasteboard payload for a Story: the card's own PNG as the sticker, with no canvas and no
    /// background keys, so nothing but the rounded square travels.
    func instagramStoryItems(for card: UIImage) -> [[String: Any]]? {
        guard let data = card.pngData() else { return nil }
        return [[Self.instagramStickerKey: data]]
    }

    /// Hands the card to Instagram Stories through its pasteboard scheme. Returns false when
    /// Instagram is not installed, so the caller falls back to the system share sheet. Requires
    /// `instagram-stories` in `LSApplicationQueriesSchemes`.
    func shareToInstagramStory(_ card: UIImage) -> Bool {
        guard
            let items = instagramStoryItems(for: card),
            let url = URL(string: "instagram-stories://share?source_application=\(Bundle.main.bundleIdentifier ?? "")"),
            UIApplication.shared.canOpenURL(url)
        else {
            return false
        }

        UIPasteboard.general.setItems(items, options: [.expirationDate: Date().addingTimeInterval(60 * 5)])
        UIApplication.shared.open(url)
        return true
    }

    func presentShareSheet(image: UIImage) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else {
            return
        }
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        if let pop = activityVC.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 40, width: 0, height: 0)
        }
        presenter.present(activityVC, animated: true)
    }
}
