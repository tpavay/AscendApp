import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import SwiftUI
import UIKit

/// Renders the composed share to an image and routes it to Photos, Instagram
/// Stories, or the system share sheet.
///
/// Photo, recap and preset backgrounds compose to a still through
/// `renderImage`. A video background composes to a movie through `exportVideo`
/// instead, with the overlay burned onto every frame by Core Image. Both write
/// `exportSize`, because both are the frame the climber arranged on the canvas.
@MainActor
struct ShareComposerExporter {
    /// Story-format export resolution.
    static let exportSize = CGSize(width: 1080, height: 2340)
    private let climbImageRepository: any ClimbImageRepository

    init(climbImageRepository: any ClimbImageRepository = FirebaseClimbImageRepository.shared) {
        self.climbImageRepository = climbImageRepository
    }

    /// Compose the final still image (background + stickers).
    func renderImage(viewModel: ShareComposerViewModel) async -> UIImage? {
        var backgroundOverride: UIImage?
        var backgroundOverrideIncludesClimbGradient = false
        if case .video(let url) = viewModel.background {
            backgroundOverride = await Self.posterFrame(for: url, targetSize: Self.exportSize)
        } else if case .preset(.climbImage(let climb, let variant)) = viewModel.background {
            backgroundOverride = await loadClimbArtwork(for: climb, variant: variant)
            backgroundOverrideIncludesClimbGradient = backgroundOverride != nil
        }
        let climbArtworkOverrides = await climbArtworkOverrides(for: viewModel)

        let canvas = ShareExportCanvas(
            viewModel: viewModel,
            size: Self.exportSize,
            backgroundOverride: backgroundOverride,
            backgroundOverrideIncludesClimbGradient: backgroundOverrideIncludesClimbGradient,
            climbArtworkOverrides: climbArtworkOverrides
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
    func renderOverlay(
        viewModel: ShareComposerViewModel,
        size: CGSize,
        climbArtworkOverrides: [ClimbImageVariant: UIImage] = [:]
    ) -> UIImage? {
        let canvas = ShareExportCanvas(
            viewModel: viewModel,
            size: size,
            climbArtworkOverrides: climbArtworkOverrides,
            overlayOnly: true
        )
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// Bake a card template (climb artwork + laid-out stats) to a full-resolution
    /// image, used as a ready-made background. Preload the climb artwork before
    /// rendering so ImageRenderer snapshots the real asset, not the async
    /// placeholder.
    func renderTemplate(
        _ template: ShareCardTemplate,
        context: ShareCardRenderContext,
        climb: Climb
    ) async -> UIImage? {
        let artwork = await loadClimbArtwork(for: climb, variant: .hero)
        let card = ShareCardTemplateView(
            template: template,
            context: context,
            artwork: ShareCardArtworkSource(
                climb: climb,
                overrides: artwork.map { [.hero: $0] } ?? [:]
            )
        )
        let sized = card
            .frame(width: Self.exportSize.width, height: Self.exportSize.height)
            .clipped()
        let renderer = ImageRenderer(content: sized)
        renderer.proposedSize = ProposedViewSize(Self.exportSize)
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
    ///
    /// The movie is written at `exportSize`, not at the source video's own frame.
    /// The canvas previews a video through `resizeAspectFill` inside the story
    /// frame, so a 4:3 clip is already shown cropped to it while the climber
    /// arranges the stickers; exporting the source frame instead handed back a
    /// composition nobody composed, and a share that letterboxed on the phone it
    /// came from.
    func exportVideo(viewModel: ShareComposerViewModel) async -> URL? {
        guard case .video(let url) = viewModel.background else { return nil }
        let asset = AVURLAsset(url: url)
        let climbArtworkOverrides = await climbArtworkOverrides(for: viewModel)

        guard let overlay = renderOverlay(
            viewModel: viewModel,
            size: Self.exportSize,
            climbArtworkOverrides: climbArtworkOverrides
        ),
              let overlayCI = CIImage(image: overlay) else {
            return nil
        }
        return await Self.composeVideo(
            asset: asset,
            overlay: UncheckedCIImage(image: overlayCI),
            frameSize: Self.exportSize,
            backgroundScale: viewModel.backgroundScale,
            backgroundOffset: viewModel.backgroundOffset,
            backgroundFilter: viewModel.backgroundFilter
        )
    }

    private func climbArtworkOverrides(for viewModel: ShareComposerViewModel) async -> [ClimbImageVariant: UIImage] {
        guard let climb = viewModel.climb else { return [:] }
        let variants = Set(viewModel.stickers.compactMap(\.climbImageVariant))
        guard !variants.isEmpty else { return [:] }

        var overrides: [ClimbImageVariant: UIImage] = [:]
        for variant in variants {
            overrides[variant] = await loadClimbArtwork(for: climb, variant: variant)
        }
        return overrides
    }

    private func loadClimbArtwork(for climb: Climb, variant: ClimbImageVariant) async -> UIImage? {
        await ClimbArtworkView.loadImage(
            for: climb,
            variant: variant,
            imageRepository: climbImageRepository
        )
    }

    nonisolated private static func composeVideo(
        asset: AVURLAsset,
        overlay: UncheckedCIImage,
        frameSize: CGSize,
        backgroundScale: CGFloat,
        backgroundOffset: CGSize,
        backgroundFilter: ShareBackgroundFilter
    ) async -> URL? {
        let safeScale = max(backgroundScale, 0.01)

        guard let videoComposition = await videoComposition(
            for: asset,
            overlay: overlay,
            frameSize: frameSize,
            safeScale: safeScale,
            backgroundOffset: backgroundOffset,
            backgroundFilter: backgroundFilter
        ) else {
            return nil
        }

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }
        let outURL = FileManager.default.temporaryDirectory
            .appending(path: "ascend-share-\(UUID().uuidString).mov")
        export.videoComposition = videoComposition

        do {
            try await export.export(to: outURL, as: .mov)
            return outURL
        } catch {
            return nil
        }
    }

    nonisolated private static func videoComposition(
        for asset: AVAsset,
        overlay: UncheckedCIImage,
        frameSize: CGSize,
        safeScale: CGFloat,
        backgroundOffset: CGSize,
        backgroundFilter: ShareBackgroundFilter
    ) async -> AVVideoComposition? {
        let frame = CGRect(origin: .zero, size: frameSize)
        let composition: AVVideoComposition? = await withCheckedContinuation { continuation in
            AVVideoComposition.videoComposition(with: asset) { request in
                let source = request.sourceImage
                let extent = source.extent
                let filteredSource = applyVideoColorFilter(backgroundFilter, to: source)
                    .cropped(to: extent)

                // Fill the story frame the way the canvas previews it
                // (`resizeAspectFill`), then apply the climber's own pinch and
                // pan on top of that fit - the same order the canvas applies
                // them in, so the two agree whatever shape the clip is.
                let fill = max(frame.width / extent.width, frame.height / extent.height)
                let scale = fill * safeScale
                let scaledWidth = extent.width * scale
                let scaledHeight = extent.height * scale
                let offsetX = backgroundOffset.width * frame.width
                let offsetY = backgroundOffset.height * frame.height
                let transform = CGAffineTransform(
                    a: scale,
                    b: 0,
                    c: 0,
                    d: scale,
                    tx: frame.midX - (scaledWidth / 2) - (extent.minX * scale) + offsetX,
                    ty: frame.midY - (scaledHeight / 2) - (extent.minY * scale) - offsetY
                )
                let transformedSource = filteredSource.transformed(by: transform)
                let background = CIImage(color: .black).cropped(to: frame)
                let compositedBackground = transformedSource.composited(over: background)
                let composited = overlay.image.composited(over: compositedBackground)
                request.finish(with: composited.cropped(to: frame), context: nil)
            } completionHandler: { videoComposition, _ in
                continuation.resume(returning: videoComposition)
            }
        }

        // The factory sizes the composition to the asset, so the story frame has
        // to be set afterwards on a mutable copy. Without this the handler's
        // output is scaled back down into the source video's own frame and the
        // reframing above buys nothing.
        guard let mutable = composition?.mutableCopy() as? AVMutableVideoComposition else {
            return composition
        }
        mutable.renderSize = frameSize
        return mutable
    }

    nonisolated private static func applyVideoColorFilter(_ filter: ShareBackgroundFilter, to image: CIImage) -> CIImage {
        switch filter {
        case .original, .zoomBlur, .motionBlur, .fisheye:
            return image
        case .mono:
            return colorControls(image, saturation: 0, contrast: 1.05)
        case .noir:
            return colorControls(image, saturation: 0, contrast: 1.4, brightness: -0.06)
        case .vivid:
            return colorControls(image, saturation: 1.55, contrast: 1.08)
        case .fade:
            return colorControls(image, saturation: 0.72, contrast: 0.88, brightness: 0.07)
        case .warm:
            return colorControls(colorMultiply(image, red: 1.0, green: 0.9, blue: 0.78), saturation: 1.1)
        case .cool:
            return colorControls(colorMultiply(image, red: 0.82, green: 0.9, blue: 1.0), saturation: 1.05)
        }
    }

    nonisolated private static func colorControls(
        _ image: CIImage,
        saturation: Float,
        contrast: Float = 1,
        brightness: Float = 0
    ) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = saturation
        filter.contrast = contrast
        filter.brightness = brightness
        return filter.outputImage ?? image
    }

    nonisolated private static func colorMultiply(
        _ image: CIImage,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: red, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: green, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: blue, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? image
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
