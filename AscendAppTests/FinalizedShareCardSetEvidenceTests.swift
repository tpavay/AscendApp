import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the four finalized share cards.
///
/// The existing suites prove the pieces; this one drives the shipping path a
/// climber actually takes — resolve the attempt's stats, ask the store which
/// cards the data supports, render each one over real landmark artwork at the
/// export resolution, and push the chosen card back through
/// `ShareComposerExporter` — and writes every frame out as a PNG so the card set
/// can be looked at rather than described.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct FinalizedShareCardSetEvidenceTests {
    private static let exportSize = ShareComposerExporter.exportSize

    // MARK: - The shipping set, exported

    /// The picker offers exactly Result, Poster, Sticker and Standing for a
    /// ranked climb, and each one exports full-resolution at 9:19.5.
    @Test
    func theFourRankedCardsExportAtStoryResolution() throws {
        let viewModel = Self.rankedViewModel()
        let standing = try #require(
            ResolvedShareStanding(rank: viewModel.climbRank, totalClimbers: viewModel.climbRankTotal)
        )
        let templates = ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])
        #expect(templates.map(\.id) == ["result", "poster", "sticker", "standing"])
        #expect(templates.map(\.title) == ["Result", "Poster", "Sticker", "Standing"])

        let context = Self.context(for: viewModel, standing: standing)
        for template in templates {
            let image = try #require(Self.export(template, context: context), "\(template.id) rendered nothing")
            #expect(image.size == Self.exportSize)
            #expect(
                abs(image.size.width / image.size.height - ShareCardFormat.aspectRatio) < 0.0001,
                "\(template.id) did not export at the story aspect ratio"
            )
            Self.write(image, "01-ranked-\(template.id)")
        }
    }

    /// A lone climber gets the First Ascent lockup on every card, and Standing
    /// keeps its slot with the curve replaced by copy.
    @Test
    func aLoneClimberGetsFirstAscentOnEveryCard() throws {
        let viewModel = Self.firstAscentViewModel()
        let standing = try #require(
            ResolvedShareStanding(rank: viewModel.climbRank, totalClimbers: viewModel.climbRankTotal)
        )
        #expect(standing.isFirstAscent)

        let templates = ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])
        let context = Self.context(for: viewModel, standing: standing)
        for template in templates {
            let image = try #require(Self.export(template, context: context))
            Self.write(image, "02-first-ascent-\(template.id)")
        }
    }

    /// Standing stays available at both ends of the field: the winner and the
    /// climber who beat nobody both get a card.
    @Test
    func standingRendersAtEveryPercentile() throws {
        let cases: [(name: String, rank: Int, field: Int)] = [
            ("99th-percentile-winner", 1, 1_284),
            ("mid-field", 642, 1_284),
            ("0th-percentile-last", 1_284, 1_284)
        ]
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])
                .first { $0.id == "standing" }
        )

        for scenario in cases {
            let standing = try #require(
                ResolvedShareStanding(rank: scenario.rank, totalClimbers: scenario.field)
            )
            let viewModel = Self.rankedViewModel(rank: scenario.rank, total: scenario.field)
            let image = try #require(
                Self.export(template, context: Self.context(for: viewModel, standing: standing))
            )
            Self.write(image, "03-standing-\(scenario.name)-p\(standing.percentile)")
        }
    }

    /// Splits are five step ranges whatever the tower's height: only the numbers
    /// in the range labels move between a 149-step stairwell and a 1,576-step one.
    @Test
    func theResultCardShowsFiveStepRangesForShortAndLongTowers() throws {
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb]).first { $0.id == "result" }
        )

        for tower in [(name: "short-tower-149-steps", steps: 149), (name: "long-tower-1576-steps", steps: 1_576)] {
            let viewModel = Self.rankedViewModel(recordedSteps: tower.steps)
            let splits = try #require(viewModel.splits())
            #expect(splits.stepQuintileRows.count == 5, "\(tower.name) did not produce five ranges")

            let standing = try #require(ResolvedShareStanding(rank: 4, totalClimbers: 1_284))
            let image = try #require(
                Self.export(template, context: Self.context(for: viewModel, standing: standing))
            )
            Self.write(image, "04-splits-\(tower.name)")
        }
    }

    // MARK: - The wordmark band

    /// The lockup is drawn once, in the same place, on all four cards, and the
    /// protected band under the content is where it lives. Cropping the band out
    /// of each export and comparing the ink boxes is the only way to see that the
    /// position is genuinely identical rather than merely specified once.
    @Test
    func theWordmarkSitsInAnIdenticalProtectedBandOnEveryCard() throws {
        let viewModel = Self.rankedViewModel()
        let standing = try #require(ResolvedShareStanding(rank: 4, totalClimbers: 1_284))
        let context = Self.context(for: viewModel, standing: standing)
        let templates = ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])

        let scale = Self.exportSize.width / ShareCardFormat.designSize.width
        let bandHeight = ShareCardTemplateView.wordmarkClearance * scale
        let band = CGRect(
            x: 0,
            y: Self.exportSize.height - bandHeight,
            width: Self.exportSize.width,
            height: bandHeight
        )

        // The renderer's clip leaves a partially-covered row where the card's
        // content meets the band. It is a sub-pixel seam, not content, but over
        // a full-bleed photograph it is bright enough to read as ink — so the
        // measurement starts just below it.
        let seamGuard: CGFloat = 6

        var boxes: [String: CGRect] = [:]
        var crops: [UIImage] = []
        for template in templates {
            let image = try #require(Self.export(template, context: context))
            let crop = try #require(Self.crop(image, to: band))
            crops.append(crop)

            let measured = try #require(Self.crop(image, to: CGRect(
                x: band.minX,
                y: band.minY + seamGuard,
                width: band.width,
                height: band.height - seamGuard
            )))
            var box = try #require(Self.inkBounds(of: measured), "\(template.id) drew no wordmark in the band")
            box.origin.y += seamGuard
            boxes[template.id] = box

            // Centred, small, and clear of the band's top edge — the gap between
            // the clipped content and the lockup is the protection.
            let centreOffset = abs((box.midX) - Double(crop.size.width) / 2)
            #expect(centreOffset < 4, "\(template.id) wordmark is off centre by \(centreOffset)px")
            #expect(box.height < bandHeight * 0.55, "\(template.id) wordmark outgrew its band")
            #expect(box.minY > 8, "\(template.id) wordmark touches the top of the protected band")
        }

        let reference = try #require(boxes["result"])
        for (id, box) in boxes where id != "result" {
            #expect(abs(box.minX - reference.minX) < 2, "\(id) wordmark moved horizontally")
            #expect(abs(box.minY - reference.minY) < 2, "\(id) wordmark moved vertically")
            #expect(abs(box.width - reference.width) < 2, "\(id) wordmark changed width")
            #expect(abs(box.height - reference.height) < 2, "\(id) wordmark changed height")
        }

        Self.write(try #require(Self.stack(crops)), "05-wordmark-band-result-poster-sticker-standing")
    }

    /// Result and Standing hug their content: the panel is sized by what it
    /// draws and the artwork takes the rest, so nothing but the panel's own
    /// bottom padding separates the last stat row from the wordmark's band.
    ///
    /// The tolerance is the panel's authored 12pt bottom padding plus the
    /// leftover line box under a 7pt uppercase label - 24 design points, ~3% of
    /// the card. The drift this guards against was four to eight times that: a
    /// panel that reserved a fixed height, and a Standing slot that kept the
    /// distribution curve's 310pt even on a First Ascent that draws no curve.
    @Test
    func theLastContentRowStaysAgainstTheWordmarkBandOnResultAndStanding() throws {
        let maximumGap: CGFloat = 24
        let store = ShareCardTemplateStore(bundle: .main)
        let variants: [(name: String, rank: Int, field: Int)] = [
            ("ranked", 4, 1_284),
            ("first-ascent", 1, 1)
        ]

        for variant in variants {
            let viewModel = Self.rankedViewModel(rank: variant.rank, total: variant.field)
            let standing = try #require(
                ResolvedShareStanding(rank: variant.rank, totalClimbers: variant.field)
            )
            let context = Self.context(for: viewModel, standing: standing)

            for id in ["result", "standing"] {
                let template = try #require(
                    store.templates(for: [.climb, .standing]).first { $0.id == id }
                )
                let image = try #require(Self.export(template, context: context))
                let gap = try #require(
                    Self.gapBelowLastContentRow(of: image),
                    "\(id) (\(variant.name)) drew no content above the wordmark band"
                )
                #expect(
                    gap <= maximumGap,
                    "\(id) (\(variant.name)) left \(gap)pt of dead space above the wordmark band"
                )
            }
        }
    }

    /// The card is a fixed design, so a reader at the largest accessibility size
    /// gets the same pixels as one at the default — nothing can reflow into the
    /// wordmark's band.
    @Test
    func dynamicTypeCannotReflowACardIntoTheWordmark() throws {
        let viewModel = Self.rankedViewModel()
        let standing = try #require(ResolvedShareStanding(rank: 4, totalClimbers: 1_284))
        let context = Self.context(for: viewModel, standing: standing)
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb]).first { $0.id == "result" }
        )

        let large = try #require(Self.export(template, context: context, dynamicType: .large))
        let accessibility = try #require(
            Self.export(template, context: context, dynamicType: .accessibility5)
        )
        #expect(
            try Self.differingPixelFraction(large, accessibility) == 0,
            "the card reflowed under an accessibility text size"
        )
        Self.write(accessibility, "06-result-at-accessibility5")
    }

    /// The smallest supported canvas still draws the whole card, wordmark
    /// included, because the design scales as one unit.
    @Test
    func theSmallestDeviceCanvasKeepsTheWholeCard() throws {
        let viewModel = Self.rankedViewModel()
        let standing = try #require(ResolvedShareStanding(rank: 4, totalClimbers: 1_284))
        let context = Self.context(for: viewModel, standing: standing)
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])
                .first { $0.id == "standing" }
        )

        // iPhone SE (3rd gen) portrait width, at the card's own aspect ratio.
        let size = CGSize(width: 320, height: (320 / ShareCardFormat.aspectRatio).rounded())
        let image = try #require(Self.render(template, context: context, size: size))
        #expect(image.size == size)

        let scale = size.width / ShareCardFormat.designSize.width
        let bandHeight = ShareCardTemplateView.wordmarkClearance * scale
        let crop = try #require(
            Self.crop(image, to: CGRect(x: 0, y: size.height - bandHeight, width: size.width, height: bandHeight))
        )
        let box = try #require(Self.inkBounds(of: crop), "the wordmark vanished on the smallest canvas")
        #expect(abs(box.midX - Double(crop.size.width) / 2) < 3, "the wordmark drifted off centre")
        Self.write(image, "07-standing-smallest-canvas-320pt")
    }

    // MARK: - The real export path

    /// The last mile: the chosen card becomes the composer's background and goes
    /// out through `ShareComposerExporter.renderImage`, the same call the share
    /// button makes. The export is full resolution and carries the card's own
    /// lockup once — the canvas wordmark stands down for a recap.
    @Test
    func theComposerExportsTheChosenCardAtFullResolution() async throws {
        let viewModel = Self.rankedViewModel()
        let standing = try #require(ResolvedShareStanding(rank: 4, totalClimbers: 1_284))
        let context = Self.context(for: viewModel, standing: standing)
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])
                .first { $0.id == "poster" }
        )
        let card = try #require(Self.export(template, context: context))

        viewModel.background = .recap(card)
        #expect(!viewModel.shouldRenderCanvasWordmark, "a recap must not take a second wordmark")
        #expect(!viewModel.backgroundSupportsTransform, "a recap must not be pannable off its own lockup")

        let exported = try #require(await ShareComposerExporter().renderImage(viewModel: viewModel))
        #expect(exported.size == Self.exportSize)
        Self.write(exported, "08-composer-export-poster")

        // The canvas wordmark, had it drawn, would have landed in the band the
        // card already owns; the export must match the card it was handed.
        #expect(try Self.differingPixelFraction(card, exported) < 0.02)
    }

    // MARK: - Fixtures

    private static func rankedViewModel(
        rank: Int = 4,
        total: Int = 1_284,
        recordedSteps: Int = 1_576
    ) -> ShareComposerViewModel {
        ShareComposerViewModel(
            workout: liveClimbWorkout(recordedSteps: recordedSteps),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climb: .preview,
            climbName: Climb.preview.name,
            climbRank: rank,
            climbRankTotal: total
        )
    }

    private static func firstAscentViewModel() -> ShareComposerViewModel {
        rankedViewModel(rank: 1, total: 1)
    }

    /// A recorded live climb at a believable 71 steps/min whose pace varies
    /// across the ascent, so the split bars carry both the faster-than-average
    /// and the slower treatment.
    private static func liveClimbWorkout(recordedSteps: Int) -> Workout {
        // Relative pace per bucket: a hot start, a sag through the middle, a
        // finishing kick.
        let pace: [Double] = [1.18, 1.08, 0.92, 0.86, 0.94, 1.06, 0.98, 0.9, 1.02, 1.16]
        let duration = max(Int((Double(recordedSteps) / 71 * 60).rounded()), pace.count)
        let interval = duration / pace.count
        let total = pace.reduce(0, +)

        var cumulative: [Int] = []
        var running = 0.0
        for (index, weight) in pace.enumerated() {
            running += weight
            cumulative.append(
                index == pace.count - 1
                    ? recordedSteps
                    : Int((Double(recordedSteps) * running / total).rounded())
            )
        }

        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 1_200,
            climbId: Climb.preview.id,
            targetStepCount: Climb.preview.referenceStepCount,
            stopReason: .targetReached,
            splitCurve: LiveReplaySplitCurve(intervalSeconds: interval, steps: cumulative)
        )
        let startedAt = Date(timeIntervalSince1970: 1_780_000_000)

        return Workout(
            name: "Live Climb",
            date: startedAt,
            duration: Double(interval * pace.count),
            steps: recordedSteps,
            floors: Workout.stepsToFloors(recordedSteps, stepsPerFloor: 16),
            heartRateTimeSeries: (0..<pace.count).map { index in
                HeartRateDataPoint(
                    timestamp: startedAt.addingTimeInterval(Double(index * interval)),
                    heartRate: 142 + index * 4
                )
            },
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    private static func context(
        for viewModel: ShareComposerViewModel,
        standing: ResolvedShareStanding
    ) -> ShareCardRenderContext {
        .template(
            stats: viewModel.climbStats(),
            bestEfforts: viewModel.bestEffortStats,
            weeklyTotals: viewModel.weeklyTotalStats,
            splits: viewModel.splits(),
            standing: standing
        )
    }

    /// The bundled Empire State photograph stands in for the climb's hosted hero
    /// artwork, which a test cannot download.
    private static var heroArtwork: ShareCardArtworkSource {
        let image = UIImage(named: "OnboardingLandmarkEmpireCard")
        return ShareCardArtworkSource(overrides: image.map { [.hero: $0] } ?? [:])
    }

    // MARK: - Rendering

    private static func export(
        _ template: ShareCardTemplate,
        context: ShareCardRenderContext,
        dynamicType: DynamicTypeSize? = nil
    ) -> UIImage? {
        render(template, context: context, size: exportSize, dynamicType: dynamicType)
    }

    private static func render(
        _ template: ShareCardTemplate,
        context: ShareCardRenderContext,
        size: CGSize,
        dynamicType: DynamicTypeSize? = nil
    ) -> UIImage? {
        let card = ShareCardTemplateView(template: template, context: context, artwork: heroArtwork)
            .frame(width: size.width, height: size.height)
            .clipped()
            .environment(\.dynamicTypeSize, dynamicType ?? .large)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Stacks crops vertically with a hairline between them, so the four bands
    /// can be compared in one glance.
    private static func stack(_ images: [UIImage]) -> UIImage? {
        guard let first = images.first else { return nil }
        let gap: CGFloat = 6
        let size = CGSize(
            width: first.size.width,
            height: images.reduce(0) { $0 + $1.size.height } + gap * CGFloat(images.count - 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.systemPink.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            var y: CGFloat = 0
            for image in images {
                image.draw(at: CGPoint(x: 0, y: y))
                y += image.size.height + gap
            }
        }
    }

    // MARK: - Pixel readers

    /// Bounding box of everything that reads as drawn against the crop's
    /// dominant (background) colour.
    ///
    /// The threshold is what makes this a lockup measurement rather than a noise
    /// measurement: clipping the card's content leaves a sub-pixel seam along the
    /// band's top edge that is invisible on screen but not byte-identical to the
    /// background, and counting it would put every box's origin at y = 0.
    private static func inkBounds(of image: UIImage, threshold: Int = 40) -> CGRect? {
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard let buffer = try? pixels(of: image, width: width, height: height) else { return nil }

        var histogram: [UInt32: Int] = [:]
        for index in stride(from: 0, to: buffer.count, by: 4) {
            histogram[key(buffer, index), default: 0] += 1
        }
        guard let background = histogram.max(by: { $0.value < $1.value })?.key else { return nil }
        let backgroundChannels = (
            Int(background >> 16 & 0xFF), Int(background >> 8 & 0xFF), Int(background & 0xFF)
        )

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let distance = max(
                    abs(Int(buffer[index]) - backgroundChannels.0),
                    abs(Int(buffer[index + 1]) - backgroundChannels.1),
                    abs(Int(buffer[index + 2]) - backgroundChannels.2)
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

    /// Design points between the lowest row of the card that draws anything and
    /// the top of the wordmark's protected band.
    ///
    /// The panel under the artwork is a flat fill, so the reference colour is
    /// sampled from the strip immediately above the band - which the clearance
    /// guarantees is empty - and the scan walks up until a row departs from it.
    private static func gapBelowLastContentRow(
        of image: UIImage,
        threshold: Int = 40
    ) -> CGFloat? {
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard let buffer = try? pixels(of: image, width: width, height: height) else { return nil }

        let scale = image.size.width / ShareCardFormat.designSize.width
        // Clipping the card's content at the band leaves a sub-pixel seam that is
        // invisible on screen but not byte-identical to the fill under it.
        let seamGuard = 3
        let bandTop = Int((ShareCardFormat.designSize.height - ShareCardTemplateView.wordmarkClearance) * scale) - seamGuard
        guard bandTop > 0, bandTop <= height else { return nil }

        let sampleTop = max(bandTop - Int(4 * scale), 0)
        var histogram: [UInt32: Int] = [:]
        for y in sampleTop..<bandTop {
            for x in 0..<width {
                histogram[key(buffer, (y * width + x) * 4), default: 0] += 1
            }
        }
        guard let background = histogram.max(by: { $0.value < $1.value })?.key else { return nil }
        let channels = (Int(background >> 16 & 0xFF), Int(background >> 8 & 0xFF), Int(background & 0xFF))

        for y in stride(from: bandTop - 1, through: 0, by: -1) {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let distance = max(
                    abs(Int(buffer[index]) - channels.0),
                    abs(Int(buffer[index + 1]) - channels.1),
                    abs(Int(buffer[index + 2]) - channels.2)
                )
                guard distance > threshold else { continue }
                return CGFloat(bandTop + seamGuard - (y + 1)) / scale
            }
        }
        return nil
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
        let url = directory.appending(path: "finalized-\(name).png")
        try? data.write(to: url)
        print("evidence: \(url.path())")
    }
}
