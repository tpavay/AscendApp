import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the four finalized share cards.
///
/// The existing suites prove the pieces; this one drives the shipping path a
/// climber actually takes - resolve the attempt's stats, ask the store which
/// cards the data supports, lay each one out over real landmark artwork at the
/// export resolution, and push the chosen card back through
/// `ShareComposerExporter` - and photographs every frame under
/// `ASCEND_EVIDENCE_DIR`, so the card set can be looked at rather than
/// described. Every measurement reads a 1x layout, which at the export size is
/// the export itself, and holds facts rather than bitmaps (`RenderedScreen`).
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
            try Self.withCardPixels(template, context: context) { pixels in
                #expect(pixels.size == Self.exportSize)
                #expect(
                    abs(pixels.size.width / pixels.size.height - ShareCardFormat.aspectRatio) < 0.0001,
                    "\(template.id) did not export at the story aspect ratio"
                )
            }
            try Self.photograph(template, context: context, named: "01-ranked-\(template.id)")
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
            try Self.photograph(template, context: context, named: "02-first-ascent-\(template.id)")
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
            try Self.photograph(
                template,
                context: Self.context(for: viewModel, standing: standing),
                named: "03-standing-\(scenario.name)-p\(standing.percentile)"
            )
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
            try Self.photograph(
                template,
                context: Self.context(for: viewModel, standing: standing),
                named: "04-splits-\(tower.name)"
            )
        }
    }

    // MARK: - The wordmark band

    /// The lockup is drawn once, in the same place, on all four cards, and the
    /// protected band under the content is where it lives. Reading the band out
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
        // a full-bleed photograph it is bright enough to read as ink - so the
        // measurement starts just below it.
        let seamGuard: CGFloat = 6
        let measured = CGRect(
            x: band.minX,
            y: band.minY + seamGuard,
            width: band.width,
            height: band.height - seamGuard
        )

        var boxes: [String: CGRect] = [:]
        for template in templates {
            var box = try Self.withCardPixels(template, context: context) { pixels in
                try #require(
                    Self.inkBounds(of: pixels, in: measured),
                    "\(template.id) drew no wordmark in the band"
                )
            }
            // In the band's own coordinates, so the clearance from its top edge reads directly.
            box.origin.y -= band.minY
            boxes[template.id] = box

            // Centred, small, and clear of the band's top edge - the gap between
            // the clipped content and the lockup is the protection.
            let centreOffset = abs(box.midX - band.width / 2)
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

        if RenderedScreen.isPhotographing {
            let sheet = WordmarkBandProofSheet(
                cards: templates.map { Self.card($0, context: context) },
                band: band.size
            )
            try RenderedScreen.photograph(
                sheet,
                named: "finalized-05-wordmark-band-result-poster-sticker-standing",
                scale: 1,
                proposedSize: ProposedViewSize(sheet.size)
            )
        }
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
                let gap = try Self.withCardPixels(template, context: context) { pixels in
                    try #require(
                        Self.gapBelowLastContentRow(of: pixels),
                        "\(id) (\(variant.name)) drew no content above the wordmark band"
                    )
                }
                #expect(
                    gap <= maximumGap,
                    "\(id) (\(variant.name)) left \(gap)pt of dead space above the wordmark band"
                )
            }
        }
    }

    /// The bottom gap is only half the story: a slot reserved for something a
    /// variant does not draw opens its void *between* two content rows, where a
    /// bottom-anchored measurement cannot see it. This reads the void directly -
    /// the tallest run of identical rows anywhere above the wordmark band.
    ///
    /// Real breathing room between rows measures under 35 design points on every
    /// card, so the tolerance is 48 - about 5.7% of the card. Restoring the
    /// Standing slot's old fixed 310pt height, the drift this guards against,
    /// measures 95pt ranked and 246pt on a First Ascent that draws no curve.
    @Test
    func noVariantReservesASlotItDoesNotDraw() throws {
        let maximumFlatBand: CGFloat = 48
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
                let band = try Self.withCardPixels(template, context: context) { pixels in
                    try #require(Self.tallestFlatBandAboveWordmark(of: pixels))
                }
                #expect(
                    band <= maximumFlatBand,
                    "\(id) (\(variant.name)) left a \(band)pt band of nothing inside the card"
                )
            }
        }
    }

    /// The card is a fixed design, so a reader at the largest accessibility size
    /// gets the same pixels as one at the default - nothing can reflow into the
    /// wordmark's band.
    @Test
    func dynamicTypeCannotReflowACardIntoTheWordmark() throws {
        let viewModel = Self.rankedViewModel()
        let standing = try #require(ResolvedShareStanding(rank: 4, totalClimbers: 1_284))
        let context = Self.context(for: viewModel, standing: standing)
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb]).first { $0.id == "result" }
        )

        // One card's pixels are held as a list while the other is laid out, so the two
        // layouts never exist at once.
        let whole = CGRect(origin: .zero, size: Self.exportSize)
        let large = try Self.withCardPixels(template, context: context, dynamicType: .large) { pixels in
            pixels.pixels(in: whole)
        }
        let differing = try Self.withCardPixels(template, context: context, dynamicType: .accessibility5) { pixels in
            Self.differingPixelFraction(large, pixels.pixels(in: whole))
        }
        #expect(differing == 0, "the card reflowed under an accessibility text size")
        try Self.photograph(template, context: context, dynamicType: .accessibility5, named: "06-result-at-accessibility5")
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
        let scale = size.width / ShareCardFormat.designSize.width
        let bandHeight = ShareCardTemplateView.wordmarkClearance * scale
        let band = CGRect(x: 0, y: size.height - bandHeight, width: size.width, height: bandHeight)

        let box = try Self.withCardPixels(template, context: context, size: size) { pixels -> CGRect in
            #expect(pixels.size == size)
            return try #require(Self.inkBounds(of: pixels, in: band), "the wordmark vanished on the smallest canvas")
        }
        #expect(abs(box.midX - size.width / 2) < 3, "the wordmark drifted off centre")
        try Self.photograph(template, context: context, size: size, named: "07-standing-smallest-canvas-320pt")
    }

    // MARK: - The real export path

    /// The last mile: the chosen card becomes the composer's background and goes
    /// out through `ShareComposerExporter.renderImage`, the same call the share
    /// button makes. The export is full resolution and carries the card's own
    /// lockup once - the canvas wordmark stands down for a recap.
    @Test
    func theComposerExportsTheChosenCardAtFullResolution() async throws {
        let viewModel = Self.rankedViewModel()
        let standing = try #require(ResolvedShareStanding(rank: 4, totalClimbers: 1_284))
        let context = Self.context(for: viewModel, standing: standing)
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb, .standing])
                .first { $0.id == "poster" }
        )
        let card = try #require(Self.exportImage(template, context: context))

        viewModel.background = .recap(card)
        #expect(!viewModel.shouldRenderCanvasWordmark, "a recap must not take a second wordmark")
        #expect(!viewModel.backgroundSupportsTransform, "a recap must not be pannable off its own lockup")

        let exported = try #require(await ShareComposerExporter().renderImage(viewModel: viewModel))
        #expect(exported.size == Self.exportSize)
        try RenderedScreen.photograph(
            Image(uiImage: exported)
                .resizable()
                .frame(width: Self.exportSize.width, height: Self.exportSize.height),
            named: "finalized-08-composer-export-poster",
            scale: 1,
            proposedSize: ProposedViewSize(Self.exportSize)
        )

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

    /// The card as the exporter lays it out: full-bleed at `size`, at a fixed text size.
    private static func card(
        _ template: ShareCardTemplate,
        context: ShareCardRenderContext,
        size: CGSize = exportSize,
        dynamicType: DynamicTypeSize? = nil
    ) -> some View {
        ShareCardTemplateView(template: template, context: context, artwork: heroArtwork)
            .frame(width: size.width, height: size.height)
            .clipped()
            .environment(\.dynamicTypeSize, dynamicType ?? .large)
    }

    /// Lays the card out at 1x - `size` is already the export's own resolution, so 1x is the
    /// export itself - and hands `body` its pixels, released on return. Every pixel reader below
    /// relies on that: at 1x a pixel is a point, so the card's coordinates need no conversion.
    private static func withCardPixels<Result>(
        _ template: ShareCardTemplate,
        context: ShareCardRenderContext,
        size: CGSize = exportSize,
        dynamicType: DynamicTypeSize? = nil,
        _ body: (PixelSampler) throws -> Result
    ) throws -> Result {
        try RenderedScreen.withOffscreenPixels(
            of: card(template, context: context, size: size, dynamicType: dynamicType),
            scale: 1,
            proposedSize: ProposedViewSize(size),
            body
        )
    }

    /// The export as the app receives it, for the one test that hands the card back to the
    /// composer as its recap background - a fixture the app consumes, not a bitmap a test reads.
    private static func exportImage(
        _ template: ShareCardTemplate,
        context: ShareCardRenderContext
    ) -> UIImage? {
        let renderer = ImageRenderer(content: card(template, context: context))
        renderer.proposedSize = ProposedViewSize(exportSize)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Writes the card at its own resolution to `ASCEND_EVIDENCE_DIR`, and does nothing otherwise.
    private static func photograph(
        _ template: ShareCardTemplate,
        context: ShareCardRenderContext,
        size: CGSize = exportSize,
        dynamicType: DynamicTypeSize? = nil,
        named name: String
    ) throws {
        try RenderedScreen.photograph(
            card(template, context: context, size: size, dynamicType: dynamicType),
            named: "finalized-\(name)",
            scale: 1,
            proposedSize: ProposedViewSize(size)
        )
    }

    // MARK: - Pixel readers

    /// Bounding box, in points, of everything inside `region` that reads as drawn
    /// against the region's dominant (background) colour.
    ///
    /// The threshold is what makes this a lockup measurement rather than a noise
    /// measurement: clipping the card's content leaves a sub-pixel seam along the
    /// band's top edge that is invisible on screen but not byte-identical to the
    /// background, and counting it would put every box's origin at the band's top.
    private static func inkBounds(of pixels: PixelSampler, in region: CGRect, threshold: Int = 40) -> CGRect? {
        guard let background = dominantColour(of: pixels, in: region) else { return nil }
        return pixels.bounds(in: region) { distance(from: $0, to: background) > threshold }
    }

    /// Design points between the lowest row of the card that draws anything and
    /// the top of the wordmark's protected band.
    ///
    /// The panel under the artwork is a flat fill, so the reference colour is
    /// sampled from the strip immediately above the band - which the clearance
    /// guarantees is empty - and the scan walks up until a row departs from it.
    private static func gapBelowLastContentRow(
        of pixels: PixelSampler,
        threshold: Int = 40
    ) -> CGFloat? {
        let width = pixels.width
        let height = pixels.height

        let scale = pixels.size.width / ShareCardFormat.designSize.width
        // Clipping the card's content at the band leaves a sub-pixel seam that is
        // invisible on screen but not byte-identical to the fill under it.
        let seamGuard = 3
        let bandTop = Int((ShareCardFormat.designSize.height - ShareCardTemplateView.wordmarkClearance) * scale) - seamGuard
        guard bandTop > 0, bandTop <= height else { return nil }

        let sampleTop = max(bandTop - Int(4 * scale), 0)
        guard let background = dominantColour(
            of: pixels,
            in: CGRect(x: 0, y: sampleTop, width: width, height: bandTop - sampleTop)
        ) else { return nil }

        for y in stride(from: bandTop - 1, through: 0, by: -1) {
            for x in 0..<width where distance(from: pixels.pixel(x: x, y: y), to: background) > threshold {
                return CGFloat(bandTop + seamGuard - (y + 1)) / scale
            }
        }
        return nil
    }

    /// Tallest run of pixel-identical rows above the wordmark band, in design
    /// points.
    ///
    /// A run of identical rows is a strip of the card that draws nothing:
    /// artwork never repeats a row, a gradient never repeats a row, and text
    /// and bars break the run the moment they start. Spacing between rows makes
    /// short runs; a reserved slot makes a long one.
    private static func tallestFlatBandAboveWordmark(of pixels: PixelSampler) -> CGFloat? {
        let scale = pixels.size.width / ShareCardFormat.designSize.width
        let bandTop = Int(
            (ShareCardFormat.designSize.height - ShareCardTemplateView.wordmarkClearance) * scale
        )
        guard bandTop > 1, bandTop <= pixels.height else { return nil }

        func row(_ y: Int) -> [RGBA] {
            pixels.pixels(in: CGRect(x: 0, y: y, width: pixels.width, height: 1))
        }

        var tallest = 0
        var run = 1
        var previous = row(0)
        for y in 1..<bandTop {
            let current = row(y)
            if current == previous {
                run += 1
                tallest = max(tallest, run)
            } else {
                run = 1
            }
            previous = current
        }
        return CGFloat(tallest) / scale
    }

    /// The most common colour inside `region`, in points.
    private static func dominantColour(of pixels: PixelSampler, in region: CGRect) -> RGBA? {
        var histogram: [UInt32: Int] = [:]
        for pixel in pixels.pixels(in: region) {
            histogram[key(pixel), default: 0] += 1
        }
        guard let background = histogram.max(by: { $0.value < $1.value })?.key else { return nil }
        return RGBA(
            red: UInt8(background >> 16 & 0xFF),
            green: UInt8(background >> 8 & 0xFF),
            blue: UInt8(background & 0xFF),
            alpha: 255
        )
    }

    private static func key(_ pixel: RGBA) -> UInt32 {
        UInt32(pixel.red) << 16 | UInt32(pixel.green) << 8 | UInt32(pixel.blue)
    }

    /// The largest per-channel difference between two colours, alpha ignored.
    private static func distance(from pixel: RGBA, to reference: RGBA) -> Int {
        max(
            abs(Int(pixel.red) - Int(reference.red)),
            abs(Int(pixel.green) - Int(reference.green)),
            abs(Int(pixel.blue) - Int(reference.blue))
        )
    }

    /// The share of positions whose colour differs between two same-sized captures.
    private static func differingPixelFraction(_ lhs: [RGBA], _ rhs: [RGBA]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        var differing = 0
        for (left, right) in zip(lhs, rhs) where
            left.red != right.red || left.green != right.green || left.blue != right.blue {
            differing += 1
        }
        return Double(differing) / Double(lhs.count)
    }

    /// The same comparison for the two images the composer path deals in: the recap
    /// fixture the app was handed and the export it returned. Both are the app's
    /// `UIImage`s rather than a test's capture, so they are read here rather than
    /// through `RenderedScreen`.
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
}

/// The protected band of every card, stacked with a hairline between them so the
/// four lockups can be compared in one glance. Built only to be photographed.
private struct WordmarkBandProofSheet<Card: View>: View {
    let cards: [Card]
    let band: CGSize

    private static var gap: CGFloat { 6 }

    var size: CGSize {
        CGSize(
            width: band.width,
            height: band.height * CGFloat(cards.count) + Self.gap * CGFloat(max(cards.count - 1, 0))
        )
    }

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                card
                    .frame(width: band.width, height: band.height, alignment: .bottom)
                    .clipped()
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.pink)
    }
}
