import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the pre-formatted stat clusters.
///
/// Every cluster the approved review page settled on is placed on a real
/// photograph and pushed through `ShareComposerExporter.renderImage` — the same
/// call the share button makes — then written out as a full-resolution PNG, so
/// the set can be looked at rather than described. The measurements alongside
/// each render are the two rules a cluster cannot be trusted to keep on its own:
/// it draws plate-free, and it does not put a second wordmark on the export.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareStatClusterPresetEvidenceTests {
    private static let exportSize = ShareComposerExporter.exportSize

    /// Every cluster a ranked climb supports, exported over a tower photograph.
    @Test
    func everyClimbClusterExportsOverAPhotographAtStoryResolution() async throws {
        let viewModel = Self.liveClimbViewModel()
        let presets = viewModel.availablePresets()
        #expect(
            presets.map(\.id) == ["hero", "rank", "row", "splits", "receipt", "minimal",
                                  "hr-hero", "hr-row", "full-grid", "hr-minimal"],
            "the climb picker changed shape"
        )

        for (index, preset) in presets.enumerated() {
            let image = try #require(
                await Self.export(preset, on: viewModel),
                "\(preset.id) rendered nothing"
            )
            #expect(image.size == Self.exportSize)
            #expect(
                abs(image.size.width / image.size.height - ShareCardFormat.aspectRatio) < 0.0001,
                "\(preset.id) did not export at the story aspect ratio"
            )
            Self.write(image, String(format: "01-%02d-climb-%@", index + 1, preset.id))
        }
    }

    /// A routine and a Just Climb reach the same export path, and each gets the
    /// clusters its own data supports.
    @Test
    func aRoutineAndAJustClimbExportTheirOwnClusters() async throws {
        let sessions: [(name: String, viewModel: ShareComposerViewModel)] = [
            ("routine", Self.routineViewModel()),
            ("just-climb", Self.justClimbViewModel())
        ]

        for session in sessions {
            let presets = session.viewModel.availablePresets()
            #expect(!presets.isEmpty, "\(session.name) was offered nothing")
            for preset in presets {
                let image = try #require(
                    await Self.export(preset, on: session.viewModel),
                    "\(session.name)/\(preset.id) rendered nothing"
                )
                #expect(image.size == Self.exportSize)
                Self.write(image, "02-\(session.name)-\(preset.id)")
            }
        }
    }

    /// Plate-free is the default and it is visible: the same cluster on the same
    /// photograph, before and after the edit rail's existing panel control.
    @Test
    func theSamePhotographShowsThePlateFreeDefaultAndTheOptionalPanel() async throws {
        let viewModel = Self.liveClimbViewModel()
        let hero = try #require(viewModel.availablePresets().first { $0.id == "hero" })

        let plateFree = try #require(await Self.export(hero, on: viewModel, keepSticker: true))
        Self.write(plateFree, "03-hero-plate-free")

        let id = try #require(viewModel.stickers.first?.id)
        viewModel.cycleTextBackground(for: id)
        let plated = try #require(await ShareComposerExporter().renderImage(viewModel: viewModel))
        Self.write(plated, "04-hero-with-panel")

        // A panel is a large opaque area the photograph no longer shows through.
        #expect(
            try Self.differingPixelFraction(plateFree, plated) > 0.02,
            "adding a panel changed almost nothing, so the default was not plate-free"
        )
        viewModel.deleteSticker(id)
    }

    /// A recap only skips the automatic stats sheet: a cluster still lands on
    /// one, and the recap's burned-in lockup stays the export's only wordmark.
    @Test
    func aClusterExportsOnTopOfARecapBackground() async throws {
        let viewModel = Self.liveClimbViewModel()
        let standing = try #require(
            ResolvedShareStanding(rank: viewModel.climbRank, totalClimbers: viewModel.climbRankTotal)
        )
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])
                .first { $0.id == "result" }
        )
        let recap = try #require(
            await ShareComposerExporter().renderTemplate(
                template,
                context: .template(
                    stats: viewModel.climbStats(),
                    bestEfforts: viewModel.bestEffortStats,
                    weeklyTotals: viewModel.weeklyTotalStats,
                    splits: viewModel.splits(),
                    standing: standing
                ),
                climb: .preview
            )
        )

        viewModel.resetForNewBackground(.recap(recap))
        #expect(!viewModel.shouldRenderCanvasWordmark, "a recap must not take a second wordmark")

        let row = try #require(viewModel.availablePresets().first { $0.id == "row" })
        viewModel.addPresetSticker(row)
        var placed = try #require(viewModel.stickers.first)
        // Off the card's own content, in the space a climber would drop it.
        placed.position = CGPoint(x: 0.5, y: 0.18)
        viewModel.update(placed)

        let image = try #require(await ShareComposerExporter().renderImage(viewModel: viewModel))
        #expect(image.size == Self.exportSize)
        #expect(
            try Self.differingPixelFraction(recap, image) > 0.001,
            "the cluster did not draw on top of the recap"
        )
        Self.write(image, "05-row-on-recap")
    }

    /// The lockup is drawn once, bottom center, whatever the cluster does. Every
    /// export's band is measured against a bare canvas's, so a cluster that
    /// spelled the brand or shifted the lockup shows up as a different ink box.
    @Test
    func theCanvasWordmarkStaysTheOnlyOneOnEveryCluster() async throws {
        let viewModel = Self.liveClimbViewModel()
        let bare = try #require(await ShareComposerExporter().renderImage(viewModel: viewModel))
        let band = Self.wordmarkBand
        let bareBand = try #require(Self.crop(bare, to: band))
        let reference = try #require(Self.inkBounds(of: bareBand), "the bare canvas drew no wordmark")

        for preset in viewModel.availablePresets() {
            let image = try #require(await Self.export(preset, on: viewModel))
            let cropped = try #require(Self.crop(image, to: band))
            let box = try #require(Self.inkBounds(of: cropped), "\(preset.id) lost the wordmark")
            #expect(abs(box.minX - reference.minX) < 3, "\(preset.id) moved the wordmark horizontally")
            #expect(abs(box.minY - reference.minY) < 3, "\(preset.id) moved the wordmark vertically")
            #expect(abs(box.width - reference.width) < 3, "\(preset.id) changed the wordmark's width")
            #expect(abs(box.height - reference.height) < 3, "\(preset.id) changed the wordmark's height")
        }
    }

    /// The case bare white text actually loses: a blown-out photograph. Every
    /// cluster goes over pure white, where the type itself is invisible and the
    /// only thing that can be read is the treatment around it.
    @Test
    func everyClusterStaysReadableOnAWhiteout() async throws {
        let viewModel = Self.liveClimbViewModel()
        viewModel.background = .photo(Self.whiteout)

        for preset in viewModel.availablePresets() {
            let image = try #require(await Self.export(preset, on: viewModel))
            let ink = try Self.inkFraction(of: image)
            #expect(
                ink > 0.004,
                "\(preset.id) laid down almost no ink on a white background (\(ink)) - it would read as blank"
            )
            Self.write(image, "06-whiteout-\(preset.id)")
        }
    }

    /// The mechanism, measured at the size it exists for.
    ///
    /// Over pure white the glyph contributes nothing, so the ink on the canvas is
    /// exactly what the treatment put there. An untreated caption is invisible; a
    /// drop shadow alone is thin at this size; the outline is what puts an edge
    /// back on it. If this ordering ever inverts, small labels are washing out
    /// again whatever the code claims.
    @Test
    func theOutlineIsWhatHoldsSmallTextUpNotTheShadow() throws {
        var ink: [ShareCardTextLegibility: Double] = [:]
        for treatment in [ShareCardTextLegibility.none, .shadow, .outline] {
            let node = ShareCardNode(.text(ShareCardText(
                segments: [ShareCardTextSegment(literal: "SPLITS BY STEP")],
                style: ShareCardTextStyle(
                    size: 11.6,          // the clusters' caption size
                    tracking: 2.3,
                    tint: ShareCardTint(.value),
                    legibility: treatment
                )
            )))
            let rendered = try #require(Self.renderOnWhite(node))
            ink[treatment] = try Self.inkFraction(of: rendered)
            Self.write(rendered, "07-caption-on-white-\(treatment.rawValue)")
        }

        let bare = try #require(ink[ShareCardTextLegibility.none])
        let shadowed = try #require(ink[ShareCardTextLegibility.shadow])
        let outlined = try #require(ink[ShareCardTextLegibility.outline])
        #expect(bare < 0.001, "untreated white text on white should be invisible, measured \(bare)")
        #expect(shadowed > bare, "the contact shadow put no ink down")
        #expect(
            outlined > shadowed * 1.5,
            "the outline (\(outlined)) barely beat the shadow alone (\(shadowed)) at caption size"
        )
    }

    /// A caption drawn on white at export scale, so the measurement is of the
    /// pixels a climber would actually be shown.
    private static func renderOnWhite(_ node: ShareCardNode) -> UIImage? {
        let content = ZStack {
            Color.white
            ShareCardRenderer(node: node, context: ShareCardRenderContext())
                .fixedSize()
                .scaleEffect(exportSize.width / ShareCardFormat.designSize.width)
        }
        .frame(width: 400, height: 120)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Fraction of pixels meaningfully darker than white.
    private static func inkFraction(of image: UIImage, threshold: Int = 205) throws -> Double {
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        let buffer = try pixels(of: image, width: width, height: height)

        var dark = 0
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let luminance = (Int(buffer[index]) * 21 + Int(buffer[index + 1]) * 72 + Int(buffer[index + 2]) * 7) / 100
            if luminance < threshold { dark += 1 }
        }
        return Double(dark) / Double(width * height)
    }

    /// The add sheet previews each cluster inside one fixed design box so every
    /// tile shows the same reduction. A cluster that outgrew the box would be
    /// clipped in the picker and only in the picker, which is the kind of defect
    /// nobody notices until a climber picks the wrong thing.
    @Test
    func everyClusterFitsTheAddSheetsPreviewBox() throws {
        let box = ShareAddStatSheetLayout.presetPreviewBox
        for viewModel in [Self.liveClimbViewModel(), Self.routineViewModel(), Self.justClimbViewModel()] {
            for preset in viewModel.availablePresets() {
                let content = viewModel.presetPreview(for: preset)
                let size = try #require(Self.intrinsicSize(of: content))
                #expect(
                    size.width <= box.width && size.height <= box.height,
                    "\(preset.id) measures \(size) and does not fit the \(box) preview tile"
                )
            }
        }
    }

    /// What the cluster actually lays out at, with no size proposed to it —
    /// the same `fixedSize()` the canvas and the tile both render it under.
    private static func intrinsicSize(of content: ShareStickerContent) -> CGSize? {
        let renderer = ImageRenderer(
            content: ShareCardRenderer(node: content.node, context: content.context).fixedSize()
        )
        return renderer.uiImage?.size
    }

    /// A cluster is fixed art, so a reader at the largest accessibility text
    /// size gets the pixels the author saw.
    @Test
    func dynamicTypeCannotReflowACluster() throws {
        let viewModel = Self.liveClimbViewModel()
        let hero = try #require(viewModel.availablePresets().first { $0.id == "hero" })
        viewModel.addPresetSticker(hero)
        defer { viewModel.stickers.removeAll() }

        let large = try #require(Self.render(viewModel, dynamicType: .large))
        let accessibility = try #require(Self.render(viewModel, dynamicType: .accessibility5))
        #expect(
            try Self.differingPixelFraction(large, accessibility) == 0,
            "the cluster reflowed under an accessibility text size"
        )
    }

    // MARK: - Rendering

    /// Places the cluster, exports the canvas, and clears it again unless the
    /// caller wants to keep editing the one it just placed.
    private static func export(
        _ preset: ShareStatClusterPreset,
        on viewModel: ShareComposerViewModel,
        keepSticker: Bool = false
    ) async -> UIImage? {
        viewModel.stickers.removeAll()
        viewModel.addPresetSticker(preset)
        let image = await ShareComposerExporter().renderImage(viewModel: viewModel)
        if !keepSticker { viewModel.stickers.removeAll() }
        return image
    }

    private static func render(
        _ viewModel: ShareComposerViewModel,
        dynamicType: DynamicTypeSize
    ) -> UIImage? {
        let canvas = ShareExportCanvas(viewModel: viewModel, size: exportSize)
            .environment(\.dynamicTypeSize, dynamicType)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The strip the canvas lockup lives in, in export pixels.
    private static var wordmarkBand: CGRect {
        let height = exportSize.height * 0.06
        return CGRect(x: 0, y: exportSize.height - height, width: exportSize.width, height: height)
    }

    // MARK: - Fixtures

    private static func liveClimbViewModel() -> ShareComposerViewModel {
        let viewModel = ShareComposerViewModel(
            workout: ShareStatClusterPresetTests.recordedWorkout(
                name: "Live Climb",
                trackingMode: .liveClimb,
                climbId: Climb.preview.id,
                heartRate: true
            ),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climb: .preview,
            climbName: Climb.preview.name,
            climbRank: 4,
            climbRankTotal: 1_284
        )
        viewModel.background = .photo(photograph)
        return viewModel
    }

    private static func routineViewModel() -> ShareComposerViewModel {
        let viewModel = ShareComposerViewModel(
            workout: ShareStatClusterPresetTests.recordedWorkout(
                name: "Pyramid 24",
                trackingMode: .routine,
                routineId: UUID().uuidString,
                heartRate: true
            ),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight
        )
        viewModel.setRoutineIntervalCount(8)
        viewModel.background = .photo(photograph)
        return viewModel
    }

    private static func justClimbViewModel() -> ShareComposerViewModel {
        let viewModel = ShareComposerViewModel(
            workout: ShareStatClusterPresetTests.recordedWorkout(
                name: "Just Climb",
                trackingMode: .justClimb,
                heartRate: false
            ),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight
        )
        viewModel.background = .photo(photograph)
        return viewModel
    }

    /// A bundled photograph stands in for the climber's own camera roll, which a
    /// test cannot reach. It is a real photograph, not a flat fill: a cluster
    /// that reads only against a solid color proves nothing.
    ///
    /// Everest, deliberately - of the bundled set it has by far the largest area
    /// of blown-out highlight (16% of pixels above 0.75 luminance, against 2% for
    /// the Empire State sunset). White type on snow is the case bare text loses,
    /// so it is the one the treatment is judged on.
    private static let photograph: UIImage = UIImage(named: "OnboardingLandmarkEverestCard") ?? UIImage()

    /// The brightest thing a camera roll can hand the composer. Nothing reads
    /// against pure white on ink alone, so this is where the outline has to be
    /// doing the work rather than the shadow.
    private static let whiteout: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 900, height: 1_950)
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
        }
    }()

    // MARK: - Pixel readers

    private static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Bounding box of everything that reads as drawn against the crop's
    /// dominant color.
    private static func inkBounds(of image: UIImage, threshold: Int = 70) -> CGRect? {
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard let buffer = try? pixels(of: image, width: width, height: height) else { return nil }

        var histogram: [UInt32: Int] = [:]
        for index in stride(from: 0, to: buffer.count, by: 4) {
            histogram[key(buffer, index), default: 0] += 1
        }
        guard let background = histogram.max(by: { $0.value < $1.value })?.key else { return nil }
        let channels = (Int(background >> 16 & 0xFF), Int(background >> 8 & 0xFF), Int(background & 0xFF))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let distance = max(
                    abs(Int(buffer[index]) - channels.0),
                    abs(Int(buffer[index + 1]) - channels.1),
                    abs(Int(buffer[index + 2]) - channels.2)
                )
                guard distance > threshold else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func key(_ buffer: [UInt8], _ index: Int) -> UInt32 {
        UInt32(buffer[index]) << 16 | UInt32(buffer[index + 1]) << 8 | UInt32(buffer[index + 2])
    }

    private static func differingPixelFraction(_ lhs: UIImage, _ rhs: UIImage) throws -> Double {
        let width = Int(max(lhs.size.width, rhs.size.width).rounded())
        let height = Int(max(lhs.size.height, rhs.size.height).rounded())
        let left = try pixels(of: lhs, width: width, height: height)
        let right = try pixels(of: rhs, width: width, height: height)

        var differing = 0
        for index in stride(from: 0, to: left.count, by: 4) where
            left[index] != right[index] || left[index + 1] != right[index + 1] ||
            left[index + 2] != right[index + 2] {
            differing += 1
        }
        return Double(differing) / Double(width * height)
    }

    private static func pixels(of image: UIImage, width: Int, height: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let cgImage = image.cgImage,
              let context = CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw EvidenceError.noBitmapContext
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private enum EvidenceError: Error { case noBitmapContext }

    // MARK: - Evidence

    private static func write(_ image: UIImage, _ name: String) {
        guard let data = image.pngData() else { return }
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            .map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory
        let url = directory.appending(path: "stat-cluster-\(name).png")
        try? data.write(to: url)
        print("evidence: \(url.path())")
    }
}
