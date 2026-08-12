import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Renders the shipping sticker and template views and reads the pixels back.
///
/// The tree-level tests prove the intent is carried; these prove it reaches the
/// image. Both defects were invisible in the model — the settings were stored
/// correctly and thrown away at draw time — so an assertion that stops at the
/// model would not have caught either one.
/// Rendering four cards at 1080×2340 and reading every pixel back holds the main
/// actor for long enough to starve a suite waiting on a hosted appearance
/// transition, so this takes the same gate they do.
@MainActor
@Suite(.hostsAWindow)
struct ShareCardRenderingTests {
    // MARK: - Defect 1, at the pixel level

    /// Under the old code the multi-metric renderer took no label-placement
    /// parameter, so all three placements produced **byte-identical** output.
    /// Every pair must now differ.
    @Test
    func aCompositeStickerDrawsEachLabelPlacementDifferently() throws {
        var images: [ShareCardLabelPlacement: UIImage] = [:]
        for placement in ShareCardLabelPlacement.allCases {
            let image = try #require(
                Self.render(Self.compositeSticker(placement: placement, layout: .column)),
                "\(placement) rendered nothing"
            )
            images[placement] = image
            Self.writeEvidence(image, named: "sticker-column-\(placement.rawValue)")
        }

        for placement in ShareCardLabelPlacement.allCases where placement != .below {
            let difference = try Self.differingPixelFraction(
                try #require(images[.below]),
                try #require(images[placement])
            )
            #expect(difference > 0.01, "\(placement) rendered the same as .below")
        }
    }

    /// The single-metric and multi-metric cases now agree, because there is one
    /// renderer: the label of a leading-placed metric sits left of its value
    /// whether the sticker holds one stat or three.
    @Test
    func leadingPlacementStaysWideWhateverTheMetricCount() throws {
        let single = try #require(Self.renderSize(Self.sticker(placement: .leading, refs: [])))
        let singleStacked = try #require(Self.renderSize(Self.sticker(placement: .above, refs: [])))
        #expect(
            single.width / single.height > singleStacked.width / singleStacked.height,
            "a leading label makes a single metric wider than a stacked one"
        )

        let extras = [ShareStatRef(kind: .duration), ShareStatRef(kind: .calories)]
        let composite = try #require(Self.renderSize(Self.sticker(placement: .leading, refs: extras, layout: .column)))
        let compositeStacked = try #require(Self.renderSize(Self.sticker(placement: .above, refs: extras, layout: .column)))
        #expect(
            composite.width / composite.height > compositeStacked.width / compositeStacked.height,
            "the same must hold once metrics are added and the arrangement changes"
        )
    }

    // MARK: - Defect 2, at the pixel level

    /// A date sticker must draw exactly what a label-less sticker draws — no
    /// `DATE` under it — while a step count keeps its unit.
    @Test
    func aDateDrawsNoLabelAndAStepCountKeepsOne() throws {
        let date = ResolvedShareStat(kind: .date, label: "DATE", value: "May 28, 2026")
        let steps = ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096")

        let dateAutomatic = try #require(Self.renderSize(Self.singleMetric(date, placement: .below)))
        let dateSuppressed = try #require(Self.renderSize(Self.singleMetric(date, placement: .none)))
        #expect(
            abs(dateAutomatic.height - dateSuppressed.height) < 0.5,
            "a date must occupy exactly the height of a value with no label"
        )

        let stepsAutomatic = try #require(Self.renderSize(Self.singleMetric(steps, placement: .below)))
        let stepsSuppressed = try #require(Self.renderSize(Self.singleMetric(steps, placement: .none)))
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

        let withExemption = try #require(Self.renderSize(Self.view(
            sticker: sticker,
            stats: [refs[0]: climbName, refs[1]: steps]
        )))

        // The same card with the exemption disabled is taller by exactly the
        // landmark label it would otherwise print.
        var forced = sticker
        forced.kind = .workoutName
        let workoutName = ResolvedShareStat(kind: .totals, label: "LANDMARK", value: "Empire State Building")
        let forcedRefs = forced.statRefs
        let withLabel = try #require(Self.renderSize(Self.view(
            sticker: forced,
            stats: [forcedRefs[0]: workoutName, forcedRefs[1]: steps]
        )))

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
        for template in templates {
            let view = ShareCardTemplateView(template: template, context: context)
                .frame(width: 1080, height: 2340)
            let image = try #require(Self.render(view, size: CGSize(width: 1080, height: 2340)),
                                     "\(template.id) rendered nothing")
            #expect(image.size.width == 1080 && image.size.height == 2340,
                    "\(template.id) must export at story resolution")
            #expect(try Self.nonBlankPixelFraction(image) > 0.02,
                    "\(template.id) rendered a blank card")
            Self.writeEvidence(image, named: template.id)
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

        let rich = try #require(Self.render(
            ShareCardTemplateView(template: summit, context: full).frame(width: 390, height: 845),
            size: CGSize(width: 390, height: 845)
        ))
        let thin = try #require(Self.render(
            ShareCardTemplateView(template: summit, context: sparse).frame(width: 390, height: 845),
            size: CGSize(width: 390, height: 845)
        ))

        #expect(try Self.nonBlankPixelFraction(thin) > 0.02, "the card must still render")
        #expect(try Self.differingPixelFraction(rich, thin) > 0.01, "missing stats must drop their cells")
    }

    @Test
    func everyCardDrawsRankAndFirstAscentAsDifferentTreatments() throws {
        let templates = try ShareCardTemplateStore(bundle: .main).loadTemplates()
        for template in templates {
            let ranked = try #require(Self.render(
                ShareCardTemplateView(template: template, context: Self.templateContext())
                    .frame(width: 390, height: 845),
                size: CGSize(width: 390, height: 845)
            ))
            let firstAscent = try #require(Self.render(
                ShareCardTemplateView(
                    template: template,
                    context: Self.templateContext(
                        standing: ResolvedShareStanding(rank: 1, totalClimbers: 1)
                    )
                )
                .frame(width: 390, height: 845),
                size: CGSize(width: 390, height: 845)
            ))

            #expect(
                try Self.differingPixelFraction(ranked, firstAscent) > 0.001,
                "\(template.id) did not change for First Ascent"
            )
            Self.writeEvidence(firstAscent, named: "\(template.id)-first-ascent")
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
                // subtitle as its detail facet — which is what the Splits Poster
                // headline reads.
                ResolvedShareStat(kind: .splits, label: splits.label, value: splits.value, detail: splits.subtitle)
            ],
            bestEfforts: [ResolvedShareStat(kind: .bestEffort, label: "FASTEST 1K", value: "9:12")],
            weeklyTotals: [],
            splits: splits,
            standing: standing
        )
    }

    // MARK: - Rendering

    /// Drops a rendered card where a reviewer can look at it: in
    /// `ASCEND_EVIDENCE_DIR` when it is set, the test host's temporary directory
    /// otherwise. The path is printed so a run can lift the images out — the
    /// fastest way to review a template edit, since templates are now data.
    static func writeEvidence(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else { return }
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            .map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory
        let url = directory.appending(path: "share-card-\(name).png")
        try? data.write(to: url)
        print("evidence: \(url.path())")
    }

    static func render(_ view: some View, size: CGSize? = nil) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let size { renderer.proposedSize = ProposedViewSize(size) }
        return renderer.uiImage
    }

    static func renderSize(_ view: some View) -> CGSize? {
        render(view)?.size
    }

    /// Fraction of pixels that differ between two same-sized renders.
    static func differingPixelFraction(_ lhs: UIImage, _ rhs: UIImage) throws -> Double {
        let width = Int(max(lhs.size.width, rhs.size.width).rounded())
        let height = Int(max(lhs.size.height, rhs.size.height).rounded())
        let left = try pixels(of: lhs, width: width, height: height)
        let right = try pixels(of: rhs, width: width, height: height)

        var differing = 0
        for index in stride(from: 0, to: left.count, by: 4) where
            left[index] != right[index] || left[index + 1] != right[index + 1] ||
            left[index + 2] != right[index + 2] || left[index + 3] != right[index + 3] {
            differing += 1
        }
        return Double(differing) / Double(width * height)
    }

    /// Fraction of pixels carrying any ink, used to catch a card that rendered
    /// its background and nothing else. Sampled every fourth pixel: this is a
    /// coarse "did anything draw" check, and scanning two megapixels of every
    /// card would hold the main actor for no extra signal.
    static func nonBlankPixelFraction(_ image: UIImage) throws -> Double {
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        let buffer = try pixels(of: image, width: width, height: height)

        var histogram: [UInt32: Int] = [:]
        var sampled = 0
        for index in stride(from: 0, to: buffer.count, by: 16) {
            let key = UInt32(buffer[index]) << 16 | UInt32(buffer[index + 1]) << 8 | UInt32(buffer[index + 2])
            histogram[key, default: 0] += 1
            sampled += 1
        }
        let dominant = histogram.values.max() ?? sampled
        return Double(sampled - dominant) / Double(sampled)
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
            throw RenderError.noBitmapContext
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    enum RenderError: Error { case noBitmapContext }
}
