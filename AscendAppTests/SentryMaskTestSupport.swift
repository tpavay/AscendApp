import AVFoundation
import Foundation
import SwiftUI
import Testing
import UIKit

/// The harness the two Sentry mask suites share: a window to render in, a real
/// movie to render, and a way to find a view in what came back.
///
/// `SentryMaskingEvidenceTests` proves each masked surface is masked and
/// `SentryMaskInteractionTests` proves the mask does not swallow that surface's
/// touches. **The two lists of surfaces are deliberately independent and stay
/// that way** - each suite keeps its own enumeration and its own assertions, so
/// neither can quietly inherit the other's blind spot. What is shared here is
/// only the plumbing underneath them, which carries no notion of which surfaces
/// exist.
@MainActor
enum SentryMaskTestHost {
    /// Puts `view` in the shared window scene, lets SwiftUI commit its platform
    /// views, and hands the laid-out window and root view to `body`.
    ///
    /// The window is torn back out on every path, so the next suite to borrow
    /// the scene finds it the way it left it.
    static func hosting<Result>(
        _ view: some View,
        size: CGSize,
        interfaceStyle: UIUserInterfaceStyle = .unspecified,
        _ body: @MainActor (UIWindow, UIView) async throws -> Result
    ) async throws -> Result {
        let controller = UIHostingController(
            rootView: view
                .frame(width: size.width, height: size.height)
                .transaction { $0.disablesAnimations = true }
        )
        controller.overrideUserInterfaceStyle = interfaceStyle
        controller.view.frame = CGRect(origin: .zero, size: size)

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: size))
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = interfaceStyle
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // A turn of the run loop so SwiftUI has committed its hosting views and
        // layers before anything walks the hierarchy.
        try await Task.sleep(for: .milliseconds(150))
        controller.view.layoutIfNeeded()

        return try await body(window, controller.view)
    }
}

/// Writes real movie files, because both mask suites need a player that actually
/// plays: `AVPlayerLayer` shows nothing without a decoded frame, and
/// `FullScreenPhotoView` asks `RemoteMediaLoader` whether an asset is playable
/// before it builds the player at all, so a stub URL never reaches the mask.
///
/// Frame content and compression are parameters rather than one baked-in
/// behaviour: the masking suite needs flat macroblocks at a high bitrate with
/// every frame a keyframe, so its fixture survives H.264 as a genuine pixel
/// permutation of its own mirror, while the interaction suite needs nothing of
/// the picture at all.
@MainActor
enum SentryMaskTestMovie {
    /// Writes a one-second movie whose every frame is `frame`.
    ///
    /// A constant movie is what makes two renders comparable: some player
    /// surfaces start playing by themselves, so nothing pins them to the same
    /// timestamp.
    static func write(
        showing frame: UIImage,
        size: CGSize,
        compressionProperties: [String: Any]? = nil,
        namePrefix: String
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(namePrefix)-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        var outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        if let compressionProperties {
            outputSettings[AVVideoCompressionPropertiesKey] = compressionProperties
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB]
        )
        writer.add(input)
        try #require(writer.startWriting(), "could not start writing the fixture movie")
        writer.startSession(atSourceTime: .zero)

        let cgFrame = try #require(frame.cgImage, "the fixture frame has no bitmap")

        for index in 0..<12 {
            let pool = try #require(adaptor.pixelBufferPool, "the writer produced no pixel buffer pool")
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixelBuffer = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) {
                context.draw(cgFrame, in: CGRect(origin: .zero, size: size))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 12))
        }

        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    /// A frame with nothing in it worth masking, for the suite that only needs
    /// the player to be real.
    static func flatFrame(size: CGSize, color: UIColor = .darkGray) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

extension UIView {
    /// Every view of `type` in this subtree, self included.
    func descendants<T: UIView>(of type: T.Type) -> [T] {
        var found = (self as? T).map { [$0] } ?? []
        for subview in subviews {
            found.append(contentsOf: subview.descendants(of: type))
        }
        return found
    }

    /// The first view of `type` in this subtree, self included.
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
