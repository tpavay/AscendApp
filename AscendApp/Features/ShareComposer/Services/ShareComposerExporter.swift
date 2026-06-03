import AVFoundation
import Photos
import SwiftUI
import UIKit

/// Renders the composed share to an image and routes it to Photos, Instagram
/// Stories, or the system share sheet.
///
/// V1: photo + preset backgrounds export fully. A video background exports a
/// still (poster frame + burned-in stickers); full motion-video export
/// (`AVVideoCompositionCoreAnimationTool`) is the documented fast-follow.
@MainActor
struct ShareComposerExporter {
    /// Story-format export resolution.
    static let exportSize = CGSize(width: 1080, height: 1920)

    /// Compose the final still image (background + stickers).
    func renderImage(viewModel: ShareComposerViewModel) async -> UIImage? {
        var posterOverride: UIImage?
        if case .video(let url) = viewModel.background {
            posterOverride = await Self.posterFrame(for: url, targetSize: Self.exportSize)
        }

        let canvas = ShareExportCanvas(
            viewModel: viewModel,
            size: Self.exportSize,
            backgroundOverride: posterOverride
        )
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Whether the composed background is a video (full export not yet supported).
    func isVideoBackground(_ viewModel: ShareComposerViewModel) -> Bool {
        viewModel.background?.isVideo ?? false
    }

    // MARK: - Save to Photos

    /// Saves the image to the Photos library (add-only permission). Returns true
    /// on success. Requires `NSPhotoLibraryAddUsageDescription` in Info.plist.
    func saveToPhotos(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Instagram Story

    /// Attempts to share directly to Instagram Stories via the pasteboard +
    /// `instagram-stories://` scheme. Returns false if Instagram isn't available
    /// (caller should fall back to the system share sheet). Requires
    /// `instagram-stories` in `LSApplicationQueriesSchemes`.
    func shareToInstagramStory(_ image: UIImage) -> Bool {
        guard
            let data = image.pngData(),
            let url = URL(string: "instagram-stories://share?source_application=\(Bundle.main.bundleIdentifier ?? "")"),
            UIApplication.shared.canOpenURL(url)
        else {
            return false
        }

        let items: [String: Any] = ["com.instagram.sharedSticker.backgroundImage": data]
        UIPasteboard.general.setItems(
            [items],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        UIApplication.shared.open(url)
        return true
    }

    // MARK: - System share sheet

    func presentShareSheet(image: UIImage) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else {
            return
        }
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        // Present from the top-most controller.
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

    // MARK: - Video poster frame

    private static func posterFrame(for url: URL, targetSize: CGSize) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = targetSize
        return await withCheckedContinuation { continuation in
            let time = CMTime(seconds: 0, preferredTimescale: 600)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                if let cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
