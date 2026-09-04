import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Lays the shipping sticker and template views out off screen and reads the pixels back.
///
/// The tree-level tests prove the intent is carried; these prove it reaches the
/// image. Both defects were invisible in the model - the settings were stored
/// correctly and thrown away at draw time - so an assertion that stops at the
/// model would not have caught either one.
///
/// Every read goes through `RenderedScreen.withOffscreenPixels` at 1x - the cards
/// were always compared at 1x - and keeps only the pixels it compares, never a
/// bitmap. Rendering four cards at 1080x2340 and reading every pixel back still
/// holds the main actor for long enough to starve a suite waiting on a hosted
/// appearance transition, so this takes the same gate they do.
@MainActor
@Suite(.hostsAWindow)
struct ShareCardRenderingTests {
    // MARK: - Defect 1, at the pixel level

    /// Under the old code the multi-metric renderer took no label-placement
    /// parameter, so all three placements produced **byte-identical** output.
    /// Every pair must now differ.
    @Test
    func aCompositeStickerDrawsEachLabelPlacementDifferently() throws {
        var rasters: [ShareCardLabelPlacement: Raster] = [:]
        for placement in ShareCardLabelPlacement.allCases {
            let sticker = Self.compositeSticker(placement: placement, layout: .column)
            rasters[placement] = try Self.raster(sticker)
            try Self.photograph(sticker, named: "sticker-column-\(placement.rawValue)")
        }

        for placement in ShareCardLabelPlacement.allCases where placement != .below {
            let difference = Self.differingPixelFraction(
                try #require(rasters[.below]),
                try #require(rasters[placement])
            )
            #expect(difference > 0.01, "\(placement) rendered the same as .below")
        }
    }

    /// The single-metric and multi-metric cases now agree, because there is one
    /// renderer: the label of a leading-placed metric sits left of its value
    /// whether the sticker holds one stat or three.
    @Test
    func leadingPlacementStaysWideWhateverTheMetricCount() throws {
        let single = try Self.renderSize(Self.sticker(placement: .leading, refs: []))
        let singleStacked = try Self.renderSize(Self.sticker(placement: .above, refs: []))
        #expect(
            single.width / single.height > singleStacked.width / singleStacked.height,
            "a leading label makes a single metric wider than a stacked one"
        )

        let extras = [ShareStatRef(kind: .duration), ShareStatRef(kind: .calories)]
        let composite = try Self.renderSize(Self.sticker(placement: .leading, refs: extras, layout: .column))
        let compositeStacked = try Self.renderSize(Self.sticker(placement: .above, refs: extras, layout: .column))
        #expect(
            composite.width / composite.height > compositeStacked.width / compositeStacked.height,
            "the same must hold once metrics are added and the arrangement changes"
        )
    }

    // MARK: - Defect 2, at the pixel level

    /// A date sticker must draw exactly what a label-less sticker draws - no
    /// `DATE` under it - while a step count keeps its unit.
    @Test
    func aDateDrawsNoLabelAndAStepCountKeepsOne() throws {
        let date = ResolvedShareStat(kind: .date, label: "DATE", value: "May 28, 2026")
        let steps = ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096")

        let dateAutomatic = try Self.renderSize(Self.singleMetric(date, placement: .below))
        let dateSuppressed = try Self.renderSize(Self.singleMetric(date, placement: .none))
        #expect(
            abs(dateAutomatic.height - dateSuppressed.height) < 0.5,
            "a date must occupy exactly the height of a value with no label"
        )

        let stepsAutomatic = try Self.renderSize(Self.singleMetric(steps, placement: .below))
        let stepsSuppressed = try Self.renderSize(Self.singleMetric(steps, placement: .none))
        #expect(
            stepsAutomatic.height > stepsSuppressed.height + 4,
            "a step count must still draw its unit"
        )
    }

    /// The exemption leaked between the two renderers: a climb name alone had no
    /// label, the same name beside another stat printed `LANDMARK`.
    @Test
    func aClimbNameKeepsItsExemptionInsideAComposite() throws {
        let climbName = ResolvedShareStat(kind: .climbName, label: "LANDMARK", value: "Empire State Building")
        let steps = ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096")

        var sticker = ShareStickerInstance(kind: .climbName, labelPlacement: .below)
        sticker.extraStats = [ShareStatRef(kind: .steps)]
        sticker.layout = .column
        let refs = sticker.statRefs

        let withExemption = try Self.renderSize(Self.view(
            sticker: sticker,
            stats: [refs[0]: climbName, refs[1]: steps]
        ))

        // The same card with the exemption disabled is taller by exactly the
        // landmark label it would otherwise print.
        var forced = sticker
        forced.kind = .workoutName
        let workoutName = ResolvedShareStat(kind: .totals, label: "LANDMARK", value: "Empire State Building")
        let forcedRefs = forced.statRefs
        let withLabel = try Self.renderSize(Self.view(
            sticker: forced,
            stats: [forcedRefs[0]: workoutName, forcedRefs[1]: steps]
        ))

        #expect(withLabel.height > withExemption.height + 4, "LANDMARK leaked into the composite")
    }

    // MARK: - Templates

    /// Every bundled template still renders. If one could not be expressed in the
    /// new format this is where it shows up.
    @Test
    func everyBundledTemplateRendersAtExportResolution() throws {
        let templates = try ShareCardTemplateStore(bundle: .main).loadTemplates()
        #expect(templates.count == 4, "the four finalized cards must all survive")

        let context = Self.templateContext()
        let exportSize = CGSize(width: 1080, height: 2340)
        for template in templates {
            let view = ShareCardTemplateView(template: template, context: context)
                .frame(width: 1080, height: 2340)
            try RenderedScreen.withOffscreenPixels(
                of: view,
                proposedSize: ProposedViewSize(exportSize)
            ) { pixels in
                #expect(pixels.size.width == 1080 && pixels.size.height == 2340,
                        "\(template.id) must export at story resolution")
                #expect(Self.nonBlankPixelFraction(pixels) > 0.02,
                        "\(template.id) rendered a blank card")
            }
            try Self.photograph(view, named: template.id, size: exportSize)
        }
    }

    /// A template that names a stat this workout has no value for drops that
    /// element rather than printing a placeholder or an empty plate.
    @Test
    func aTemplateDegradesWhenAStatIsMissing() throws {
        let templates = try ShareCardTemplateStore(bundle: .main).loadTemplates()
        let summit = try #require(templates.first { $0.id == "poster" })

        let full = Self.templateContext()
        let sparse = ShareCardRenderContext(stats: [
            ShareStatRef(kind: .climbName): ResolvedShareStat(kind: .climbName, label: "LANDMARK", value: "Empire State Building"),
            ShareStatRef(kind: .duration): ResolvedShareStat(kind: .duration, label: "DURATION", value: "22:10")
        ])

        let rich = try Self.raster(
            ShareCardTemplateView(template: summit, context: full).frame(width: 390, height: 845),
            size: CGSize(width: 390, height: 845)
        )
        let thin = try Self.raster(
            ShareCardTemplateView(template: summit, context: sparse).frame(width: 390, height: 845),
            size: CGSize(width: 390, height: 845)
        )

        #expect(Self.nonBlankPixelFraction(thin) > 0.02, "the card must still render")
        #expect(Self.differingPixelFraction(rich, thin) > 0.01, "missing stats must drop their cells")
    }

    @Test
    func everyCardDrawsRankAndFirstAscentAsDifferentTreatments() throws {
        let templates = try ShareCardTemplateStore(bundle: .main).loadTemplates()
        let cardSize = CGSize(width: 390, height: 845)
        for template in templates {
            let ranked = try Self.raster(
                ShareCardTemplateView(template: template, context: Self.templateContext())
                    .frame(width: 390, height: 845),
                size: cardSize
            )
            let firstAscentCard = ShareCardTemplateView(
                template: template,
                context: Self.templateContext(
                    standing: ResolvedShareStanding(rank: 1, totalClimbers: 1)
                )
            )
            .frame(width: 390, height: 845)
            let firstAscent = try Self.raster(firstAscentCard, size: cardSize)

            #expect(
                Self.differingPixelFraction(ranked, firstAscent) > 0.001,
                "\(template.id) did not change for First Ascent"
            )
            try Self.photograph(firstAscentCard, named: "\(template.id)-first-ascent", size: cardSize)
        }
    }

    @Test
    func exportAndFixedWordmarkUseStoryGeometry() {
        #expect(ShareCardFormat.aspectRatio == 9.0 / 19.5)
        #expect(ShareComposerExporter.exportSize == CGSize(width: 1080, height: 2340))
        #expect(ShareCardTemplateView.wordmarkClearance > ShareCardTemplateView.wordmarkSize)
        #expect(ShareCardTemplateView.wordmarkBottomInset == 22)
    }

    // MARK: - Fixtures

    static func sticker(
        placement: ShareCardLabelPlacement,
        refs: [ShareStatRef],
        layout: ShareStatLayout = .row
    ) -> some View {
        var instance = ShareStickerInstance(kind: .steps, labelPlacement: placement)
        instance.extraStats = refs
        instance.layout = layout

        let table: [ShareStatRef: ResolvedShareStat] = [
            ShareStatRef(kind: .steps): ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096"),
            ShareStatRef(kind: .duration): ResolvedShareStat(kind: .duration, label: "DURATION", value: "22:10"),
            ShareStatRef(kind: .calories): ResolvedShareStat(kind: .calories, label: "CAL", value: "317")
        ]
        return view(sticker: instance, stats: table)
    }

    static func compositeSticker(placement: ShareCardLabelPlacement, layout: ShareStatLayout) -> some View {
        sticker(
            placement: placement,
            refs: [ShareStatRef(kind: .duration), ShareStatRef(kind: .calories)],
            layout: layout
        )
    }

    static func singleMetric(_ stat: ResolvedShareStat, placement: ShareCardLabelPlacement) -> some View {
        let instance = ShareStickerInstance(kind: stat.kind, labelPlacement: placement)
        return view(sticker: instance, stats: [ShareStatRef(kind: stat.kind): stat])
    }

    static func view(sticker: ShareStickerInstance, stats: [ShareStatRef: ResolvedShareStat]) -> some View {
        let refs = sticker.statRefs.filter { stats[$0] != nil }
        let context = ShareCardRenderContext(stats: stats)
        return ShareStickerVisual(
            instance: sticker,
            content: ShareStickerContent(
                node: ShareStickerCardBuilder.node(for: sticker, resolvedRefs: refs),
                context: context,
                signature: ShareStickerContentSignature(sticker)
            ),
            climb: nil
        )
    }

    static func templateContext(
        standing: ResolvedShareStanding? = ResolvedShareStanding(rank: 7, totalClimbers: 2_460)
    ) -> ShareCardRenderContext {
        let quintileRows = (0..<5).map { index in
            ResolvedShareSplitRow(
                index: index,
                segmentText: "\(index + 1)",
                rangeText: "\(index * 409 + 1)-\((index + 1) * 409)",
                stepsText: "409",
                spmText: "\(88 + index)",
                heartRateText: nil,
                elapsedText: "4:\(10 + index)",
                isFasterThanAverage: index.isMultiple(of: 2),
                progress: 0.55 + Double(index) * 0.1
            )
        }
        let splits = ResolvedShareSplits(
            label: "SPLITS",
            value: "5 SEGMENTS",
            subtitle: "5 SEGMENTS · 82 SPM AVG",
            rows: (0..<5).map { index in
                ResolvedShareSplitRow(
                    index: index,
                    segmentText: "\(index + 1)",
                    rangeText: "\(index):00-\(index + 1):00",
                    stepsText: "8\(index)",
                    spmText: "8\(index)",
                    heartRateText: "15\(index)",
                    progress: 0.4 + Double(index) * 0.12
                )
            },
            stepQuintileRows: quintileRows,
            averageStepsPerMinuteText: "94.5",
            hasHeartRate: true
        )

        return .template(
            stats: [
                ResolvedShareStat(kind: .climbName, label: "LANDMARK", value: "Empire State Building"),
                ResolvedShareStat(kind: .climbLocation, label: "LOCATION", value: "New York, United States"),
                ResolvedShareStat(kind: .climbFloors, label: "FLOORS", value: "102"),
                ResolvedShareStat(kind: .climbRank, label: "RANK", value: "#7"),
                ResolvedShareStat(kind: .climbRankWithTotal, label: "RANK / TOTAL", value: "#7 / 2,460", detail: "2,460"),
                ResolvedShareStat(kind: .duration, label: "DURATION", value: "22:10"),
                ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096"),
                ResolvedShareStat(kind: .pace, label: "SPM", value: "94.5"),
                ResolvedShareStat(kind: .calories, label: "CAL", value: "317"),
                ResolvedShareStat(kind: .avgHeartRate, label: "AVG BPM", value: "148"),
                ResolvedShareStat(kind: .date, label: "DATE", value: "May 28, 2026"),
                // The resolver publishes splits as a stat too, carrying the
                // subtitle as its detail facet - which is what the Splits Poster
                // headline reads.
                ResolvedShareStat(kind: .splits, label: splits.label, value: splits.value, detail: splits.subtitle)
            ],
            bestEfforts: [ResolvedShareStat(kind: .bestEffort, label: "FASTEST 1K", value: "9:12")],
            weeklyTotals: [],
            splits: splits,
            standing: standing
        )
    }

    // MARK: - Reading the render back

    /// One 1x read of a card: its pixel grid, kept only as long as the comparison
    /// that needs it.
    struct Raster {
        let width: Int
        let height: Int
        let samples: [RGBA]

        /// Transparent black outside the grid, so two rasters of different sizes
        /// compare over the larger one.
        func pixel(x: Int, y: Int) -> RGBA {
            guard x >= 0, y >= 0, x < width, y < height else {
                return RGBA(red: 0, green: 0, blue: 0, alpha: 0)
            }
            return samples[y * width + x]
        }
    }

    static func raster(_ view: some View, size: CGSize? = nil) throws -> Raster {
        try RenderedScreen.withOffscreenPixels(
            of: view,
            proposedSize: size.map { ProposedViewSize($0) }
        ) { pixels in
            Raster(
                width: pixels.width,
                height: pixels.height,
                samples: pixels.pixels(in: CGRect(origin: .zero, size: pixels.size))
            )
        }
    }

    /// The size a card lays out at, in points, with nothing proposed to it.
    static func renderSize(_ view: some View) throws -> CGSize {
        try RenderedScreen.withOffscreenPixels(of: view) { $0.size }
    }

    /// Drops a rendered card where a reviewer can look at it, at the 1x the cards
    /// are compared at: in `ASCEND_EVIDENCE_DIR` when it is set, and nowhere
    /// otherwise. The fastest way to review a template edit, since templates are
    /// now data.
    static func photograph(_ view: some View, named name: String, size: CGSize? = nil) throws {
        try RenderedScreen.photograph(
            view,
            named: "share-card-\(name)",
            scale: 1,
            proposedSize: size.map { ProposedViewSize($0) }
        )
    }

    /// Fraction of pixels that differ between two renders, over the larger grid
    /// when the two laid out at different sizes.
    static func differingPixelFraction(_ lhs: Raster, _ rhs: Raster) -> Double {
        let width = max(lhs.width, rhs.width)
        let height = max(lhs.height, rhs.height)
        guard width > 0, height > 0 else { return 0 }

        var differing = 0
        for y in 0..<height {
            for x in 0..<width where lhs.pixel(x: x, y: y) != rhs.pixel(x: x, y: y) {
                differing += 1
            }
        }
        return Double(differing) / Double(width * height)
    }

    /// Fraction of pixels carrying any ink, used to catch a card that rendered
    /// its background and nothing else. Sampled every fourth pixel: this is a
    /// coarse "did anything draw" check, and scanning two megapixels of every
    /// card would hold the main actor for no extra signal.
    static func nonBlankPixelFraction(_ pixels: PixelSampler) -> Double {
        nonBlankPixelFraction(width: pixels.width, height: pixels.height) { x, y in
            pixels.pixel(x: x, y: y)
        }
    }

    static func nonBlankPixelFraction(_ raster: Raster) -> Double {
        nonBlankPixelFraction(width: raster.width, height: raster.height, raster.pixel)
    }

    private static func nonBlankPixelFraction(
        width: Int,
        height: Int,
        _ pixel: (Int, Int) -> RGBA
    ) -> Double {
        var histogram: [UInt32: Int] = [:]
        var sampled = 0
        for index in stride(from: 0, to: width * height, by: 4) {
            let sample = pixel(index % width, index / width)
            let key = UInt32(sample.red) << 16 | UInt32(sample.green) << 8 | UInt32(sample.blue)
            histogram[key, default: 0] += 1
            sampled += 1
        }
        guard sampled > 0 else { return 0 }
        let dominant = histogram.values.max() ?? sampled
        return Double(sampled - dominant) / Double(sampled)
    }
}
