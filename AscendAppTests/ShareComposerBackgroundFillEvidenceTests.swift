import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Where the stubbed climb artwork is primed in `ImageCache`. File scope so the
/// nonisolated repository stub can read it.
private let artworkURL = URL(filePath: "/ascend-tests/climb-hero.png")

/// What the captain sees when a background is chosen: the composed frame for a
/// camera-roll photo, a recap, a preset and a video, measured rather than
/// asserted from a constant.
///
/// The report was "the camera roll or the recaps are not taking up the right size
/// of the phone", with the preset climb image correct. A share is a story frame,
/// so every source has to reach the export at 1080x2340 with the frame covered
/// edge to edge - no letterbox band, whatever the source image's own aspect.
///
/// Each case exports through the shipping `ShareComposerExporter` and the PNG is
/// read back for its real pixel dimensions and for uniform bands at the four
/// edges. Nothing here trusts `exportSize`.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareComposerBackgroundFillEvidenceTests {
    /// iPhone 16 Pro, the device the report came from.
    private static let deviceSize = CGSize(width: 402, height: 874)

    @Test
    func everyBackgroundSourceExportsAFullStoryFrame() async throws {
        var report: [String] = []

        for source in try await Self.allSources() {
            let viewModel = Self.makeViewModel(background: source.background)
            let image = try #require(
                await Self.exporter().renderImage(viewModel: viewModel),
                "\(source.name) rendered nothing"
            )
            let cgImage = try #require(image.cgImage, "\(source.name) produced no bitmap")
            let pixels = CGSize(width: cgImage.width, height: cgImage.height)
            let bands = try Self.uniformEdgeBands(image)

            Self.writeEvidence(image, named: "export-\(source.name)")
            report.append("""
              \(source.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \
            \(Int(pixels.width))x\(Int(pixels.height)) px  \
            bands top \(bands.top) bottom \(bands.bottom) left \(bands.left) right \(bands.right)
            """)

            #expect(
                pixels == CGSize(width: 1080, height: 2340),
                "\(source.name) exported \(Int(pixels.width))x\(Int(pixels.height)), not the 1080x2340 story frame"
            )
            #expect(
                bands.top <= Self.bandTolerance && bands.bottom <= Self.bandTolerance,
                """
                \(source.name) letterboxed: \(bands.top) uniform rows at the top and \
                \(bands.bottom) at the bottom of a \(Int(pixels.height)) px frame.
                """
            )
            #expect(
                bands.left <= Self.bandTolerance && bands.right <= Self.bandTolerance,
                """
                \(source.name) pillarboxed: \(bands.left) uniform columns at the left and \
                \(bands.right) at the right of a \(Int(pixels.width)) px frame.
                """
            )
        }

        let text = (["Share composer export, by background source"] + report).joined(separator: "\n")
        print(text)
        Self.writeEvidence(text, named: "share-composer-background-fill")
    }

    /// A video background is the one source whose share is a movie, not a still,
    /// so `renderImage` above never runs for it. The canvas previews a video
    /// through `AVLayerVideoGravity.resizeAspectFill` inside the story frame, so
    /// the movie the climber gets has to carry that same frame.
    @Test
    func aVideoBackgroundExportsTheStoryFrameItWasComposedIn() async throws {
        let source = try await Self.videoFile()
        let viewModel = Self.makeViewModel(background: .video(source))
        let exported = try #require(
            await Self.exporter().exportVideo(viewModel: viewModel),
            "the video export produced no file"
        )
        let rendered = try #require(
            await Self.displaySize(of: exported),
            "the exported movie has no video track"
        )
        let composed = try #require(await Self.displaySize(of: source))

        // Dimensions alone would pass on a movie that reached the story frame by
        // padding the clip with black, which is the defect wearing a disguise.
        let frame = try #require(await Self.posterFrame(of: exported), "no frame came back")
        let bands = try Self.uniformEdgeBands(frame)
        Self.writeEvidence(frame, named: "export-video-frame")

        let report = """
        Share composer video export
          source video   \(Int(composed.width))x\(Int(composed.height)) px
          exported movie \(Int(rendered.width))x\(Int(rendered.height)) px
          story frame    \(Int(ShareComposerExporter.exportSize.width))x\(Int(ShareComposerExporter.exportSize.height)) px
          frame bands    top \(bands.top) bottom \(bands.bottom) left \(bands.left) right \(bands.right)
        """
        print(report)
        Self.writeEvidence(report, named: "share-composer-video-export")

        #expect(
            rendered == ShareComposerExporter.exportSize,
            """
            The composer framed this video in a \(Int(ShareComposerExporter.exportSize.width))x\
            \(Int(ShareComposerExporter.exportSize.height)) canvas and exported \
            \(Int(rendered.width))x\(Int(rendered.height)) - the source video's own frame. \
            What the climber arranged is not what lands in Photos.
            """
        )
        #expect(
            bands.top <= Self.bandTolerance && bands.bottom <= Self.bandTolerance
                && bands.left <= Self.bandTolerance && bands.right <= Self.bandTolerance,
            """
            The exported movie reached the story frame with bare canvas at its edges - \
            top \(bands.top), bottom \(bands.bottom), left \(bands.left), right \(bands.right). \
            A 9:16 clip has to be filled into the frame, not padded to it.
            """
        )
    }

    private static func posterFrame(of url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .positiveInfinity
        guard let cgImage = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func displaySize(of url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            return nil
        }
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// The frame the composer draws on screen is the frame it exports. A canvas at
    /// one aspect and an export at another is the defect the report describes,
    /// whichever of the two is wrong.
    @Test
    func theOnScreenCanvasCarriesTheExportAspect() {
        let canvas = ShareComposerView.fittedStoryCanvasSize(in: Self.deviceSize)
        let exportAspect = ShareComposerExporter.exportSize.width / ShareComposerExporter.exportSize.height

        #expect(canvas.width > 0 && canvas.height > 0)
        #expect(
            abs(canvas.width / canvas.height - exportAspect) < 0.001,
            """
            The canvas draws at \(canvas.width / canvas.height) and the export writes at \
            \(exportAspect). A background composed on one is cropped or letterboxed by the other.
            """
        )
    }

    // MARK: - Sources

    private struct Source {
        let name: String
        let background: ShareBackgroundSource
    }

    /// The four sources the picker offers, each built the way the app builds it.
    private static func allSources() async throws -> [Source] {
        let climb = Self.climb()
        Self.primeArtwork()

        let template = try #require(Self.recapTemplate(), "no bundled template requires only a climb")
        let rendered = await Self.exporter().renderTemplate(
            template,
            context: Self.templateContext(),
            climb: climb
        )
        let recap = try #require(rendered, "the recap template rendered nothing")

        let videoURL = try await Self.videoFile()

        return [
            // A real camera-roll shot: 4:3 landscape, nothing like a story frame.
            Source(name: "camera-roll", background: .photo(Self.photograph(size: CGSize(width: 4032, height: 3024)))),
            Source(name: "recap", background: .recap(recap)),
            Source(name: "preset", background: .preset(.climbImage(climb, .hero))),
            Source(name: "video", background: .video(videoURL))
        ]
    }

    private static func recapTemplate() -> ShareCardTemplate? {
        let templates = (try? ShareCardTemplateStore(bundle: .main).loadTemplates()) ?? []
        return templates.first { !$0.requires.contains(.standing) } ?? templates.first
    }

    // MARK: - Measurement

    /// A one-pixel seam at a scaled edge is rounding, not a letterbox. Anything
    /// the eye reads as a band is far above this.
    private static let bandTolerance = 2

    /// The base `ShareExportCanvas` lays under the background. A band of exactly
    /// this at an edge is canvas showing through, which is what letterboxing is.
    /// Any other flat band is the background's own art - the recap card ends in a
    /// white wordmark band by design, and calling that a letterbox would make the
    /// measurement lie.
    private static let canvasBase: UInt32 = 0x00_00_00

    private struct EdgeBands {
        let top: Int
        let bottom: Int
        let left: Int
        let right: Int
    }

    /// How many rows/columns at each edge are bare canvas - what a letterboxed or
    /// pillarboxed composition leaves behind.
    private static func uniformEdgeBands(_ image: UIImage) throws -> EdgeBands {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let buffer = try pixels(of: cgImage)

        func color(_ x: Int, _ y: Int) -> UInt32 {
            let index = (y * width + x) * 4
            return UInt32(buffer[index]) << 16 | UInt32(buffer[index + 1]) << 8 | UInt32(buffer[index + 2])
        }

        func rowIsBase(_ y: Int) -> Bool {
            !stride(from: 0, to: width, by: 4).contains { color($0, y) != canvasBase }
        }

        func columnIsBase(_ x: Int) -> Bool {
            !stride(from: 0, to: height, by: 4).contains { color(x, $0) != canvasBase }
        }

        var top = 0
        while top < height, rowIsBase(top) { top += 1 }
        var bottom = 0
        while bottom < height - top, rowIsBase(height - 1 - bottom) { bottom += 1 }
        var left = 0
        while left < width, columnIsBase(left) { left += 1 }
        var right = 0
        while right < width - left, columnIsBase(width - 1 - right) { right += 1 }

        return EdgeBands(top: top, bottom: bottom, left: left, right: right)
    }

    private static func pixels(of cgImage: CGImage) throws -> [UInt8] {
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MeasurementError.noBitmapContext
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    enum MeasurementError: Error { case noBitmapContext, noVideoWriter }

    // MARK: - Fixtures

    private static func exporter() -> ShareComposerExporter {
        ShareComposerExporter(climbImageRepository: StubClimbImageRepository())
    }

    /// The stub hands back the file URL the artwork was primed under, so the
    /// preset case exercises the real artwork path rather than the placeholder.
    private struct StubClimbImageRepository: ClimbImageRepository {
        func resolveImageURL(for climb: Climb, variant: ClimbImageVariant) async -> URL? {
            artworkURL
        }
    }


    private static func primeArtwork() {
        // Landscape, the shape climb heroes actually are.
        ImageCache.shared.store(photograph(size: CGSize(width: 2400, height: 1350)), for: artworkURL)
    }

    /// A gradient with a bright border, so a crop and a letterbox look different
    /// from each other in the evidence PNG.
    private static func photograph(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return format
        }())
        return renderer.image { context in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemPink.cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            UIColor.yellow.setStroke()
            let inset = min(size.width, size.height) * 0.04
            let path = UIBezierPath(rect: CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset))
            path.lineWidth = inset / 2
            path.stroke()
        }
    }

    /// A real one-second movie on disk. The export path reads a poster frame off
    /// an `AVURLAsset`, so a stub URL would not exercise it.
    private static func videoFile() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ascend-share-fixture-\(UUID().uuidString).mov")
        let size = CGSize(width: 1080, height: 1920)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB]
        )
        writer.add(input)
        guard writer.startWriting() else { throw MeasurementError.noVideoWriter }
        writer.startSession(atSourceTime: .zero)

        let frame = photograph(size: size)
        for index in 0..<12 {
            guard let pool = adaptor.pixelBufferPool else { throw MeasurementError.noVideoWriter }
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
            ), let cgImage = frame.cgImage {
                context.draw(cgImage, in: CGRect(origin: .zero, size: size))
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

    private static func makeViewModel(background: ShareBackgroundSource) -> ShareComposerViewModel {
        ShareComposerViewModel(
            workout: workout(),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climb: climb(),
            climbName: "Empire State Building",
            climbRank: 7,
            climbRankTotal: 2_460,
            initialBackground: background
        )
    }

    private static func workout() -> Workout {
        Workout(
            name: "Empire State Building",
            date: Date(timeIntervalSince1970: 1_750_300_000),
            duration: 1_330,
            steps: 2_096,
            floors: 106,
            source: .headphoneMotion
        )
    }

    private static func climb() -> Climb {
        Climb(
            id: "empire-state-building",
            name: "Empire State Building",
            city: "New York",
            country: "United States",
            continent: "North America",
            latitude: 40.748,
            longitude: -73.985,
            totalHeightMeters: 443,
            totalHeightFeet: 1_454,
            realClimbableHeightMeters: nil,
            realClimbableHeightFeet: nil,
            totalSteps: 2_437,
            realStairCount: 1_576,
            calculatedFloors: 102,
            category: "tower",
            tier: .gold,
            tags: [],
            funFact: "Fact",
            sourceURL: "https://example.com",
            imageSetVersion: 1,
            releaseState: .available
        )
    }

    private static func templateContext() -> ShareCardRenderContext {
        ShareCardRenderContext(
            stats: [
                ShareStatRef(kind: .climbName): ResolvedShareStat(kind: .climbName, label: "LANDMARK", value: "Empire State Building"),
                ShareStatRef(kind: .steps): ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096"),
                ShareStatRef(kind: .duration): ResolvedShareStat(kind: .duration, label: "DURATION", value: "22:10"),
                ShareStatRef(kind: .calories): ResolvedShareStat(kind: .calories, label: "CALORIES", value: "312")
            ],
            standing: ResolvedShareStanding(rank: 7, totalClimbers: 2_460)
        )
    }

    // MARK: - Evidence

    private static func evidenceDirectory() -> URL {
        ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            .map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory
    }

    private static func writeEvidence(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else { return }
        let url = evidenceDirectory().appending(path: "share-composer-\(name).png")
        try? data.write(to: url)
        print("evidence: \(url.path())")
    }

    private static func writeEvidence(_ text: String, named name: String) {
        let url = evidenceDirectory().appending(path: "\(name).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        print("evidence: \(url.path())")
    }
}
