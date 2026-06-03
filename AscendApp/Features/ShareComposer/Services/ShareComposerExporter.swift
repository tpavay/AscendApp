import AVFoundation
import CoreImage
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

    /// Whether the composed background is a video.
    func isVideoBackground(_ viewModel: ShareComposerViewModel) -> Bool {
        viewModel.background?.isVideo ?? false
    }

    /// Render just the sticker/wordmark overlay (transparent background) at the
    /// given size — used as the layer composited onto a video.
    func renderOverlay(viewModel: ShareComposerViewModel, size: CGSize) -> UIImage? {
        let canvas = ShareExportCanvas(viewModel: viewModel, size: size, overlayOnly: true)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// Bake a recap card (climb artwork + laid-out stats) to a full-resolution
    /// image, used as a ready-made background. The climb artwork must already be
    /// in memory (the Recaps tab renders the same card first, warming the cache)
    /// so this synchronous render captures it.
    func renderRecap(_ card: ShareRecapCard) -> UIImage? {
        let sized = card.frame(width: Self.exportSize.width, height: Self.exportSize.height)
        let renderer = ImageRenderer(content: sized)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    // MARK: - Save to Photos

    /// Ferries a non-Sendable `UIImage` into the nonisolated Photos change block.
    private struct UncheckedImage: @unchecked Sendable { let image: UIImage }

    /// Saves the image to the Photos library (add-only permission). Returns true
    /// on success. Requires `NSPhotoLibraryAddUsageDescription` in Info.plist.
    func saveToPhotos(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await Self.writeToLibrary(image)
    }

    /// Performs the actual library write OFF the main actor.
    ///
    /// `PHPhotoLibrary` runs the change block on its own private serial queue.
    /// A change block created inside this `@MainActor` type is implicitly
    /// inferred MainActor-isolated, so running it off-main trips
    /// `dispatch_assert_queue` and crashes with `EXC_BREAKPOINT`
    /// (see Apple DTS forum 763665 / swiftlang/swift#75453). Marking this
    /// helper `nonisolated` keeps the change block free of MainActor isolation
    /// so Photos can run it on its queue safely.
    nonisolated private static func writeToLibrary(_ image: UIImage) async -> Bool {
        let boxed = UncheckedImage(image: image)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: boxed.image)
                // Stamp "now" so it sorts as the most recent item.
                request.creationDate = Date()
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Video export (overlays composited onto the video)

    /// Ferries a non-Sendable `CIImage` into the (`@Sendable`) per-frame handler.
    private struct UncheckedCIImage: @unchecked Sendable { let image: CIImage }

    /// Exports the video background with the sticker/wordmark overlay burned in,
    /// returning a temporary file URL (or nil on failure). The overlay is
    /// rendered once and composited over every frame via Core Image.
    func exportVideo(viewModel: ShareComposerViewModel) async -> URL? {
        guard case .video(let url) = viewModel.background else { return nil }
        let asset = AVURLAsset(url: url)
        guard let renderSize = await Self.videoRenderSize(asset) else { return nil }

        // Render the overlay at the video's display size so it aligns 1:1.
        guard let overlay = renderOverlay(viewModel: viewModel, size: renderSize),
              let overlayCI = CIImage(image: overlay) else {
            return nil
        }
        return await Self.composeVideo(asset: asset, overlay: UncheckedCIImage(image: overlayCI))
    }

    /// The asset's display (orientation-applied) size.
    nonisolated private static func videoRenderSize(_ asset: AVURLAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            return nil
        }
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        let size = CGSize(width: abs(rect.width), height: abs(rect.height))
        return (size.width > 0 && size.height > 0) ? size : natural
    }

    nonisolated private static func composeVideo(asset: AVURLAsset, overlay: UncheckedCIImage) async -> URL? {
        // Composite the static overlay over every frame. The source image is
        // already display-oriented, so the same-size overlay lines up.
        let videoComposition = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            let composited = overlay.image.composited(over: source)
            request.finish(with: composited.cropped(to: source.extent), context: nil)
        }

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }
        let outURL = FileManager.default.temporaryDirectory
            .appending(path: "ascend-share-\(UUID().uuidString).mov")
        export.videoComposition = videoComposition
        export.outputURL = outURL
        export.outputFileType = .mov

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }
        return export.status == .completed ? outURL : nil
    }

    /// Saves an exported video file to Photos (add-only). See `writeToLibrary`
    /// for why the change block runs off the main actor.
    func saveVideoToPhotos(_ url: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await Self.writeVideoToLibrary(url)
    }

    nonisolated private static func writeVideoToLibrary(_ url: URL) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                // The exported file carries the source video's date metadata, so
                // Photos would otherwise file it next to the original. Stamp "now"
                // so it lands as the most recent item.
                request?.creationDate = Date()
            }
            return true
        } catch {
            return false
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

    func presentShareSheet(image: UIImage) { present(items: [image]) }
    func presentShareSheet(url: URL) { present(items: [url]) }

    private func present(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else {
            return
        }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
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
