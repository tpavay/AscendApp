import Foundation
import Testing
@testable import AscendApp

/// A date must not render the word `DATE` under it.
///
/// Not by special-casing the date: the old rule was "label everything, except one
/// hardcoded exception written inside one view", which is why the date got a
/// label and why the one exception that did exist leaked the moment the other
/// renderer ran. The rule now belongs to the stat and is read in one place.
struct ShareCardLabelPolicyTests {
    @Test
    func selfDescribingStatsDeclareThemselves() {
        for kind in [ShareStatStickerKind.date, .workoutName, .climbName, .climbRank, .climbRankWithTotal] {
            #expect(kind.isSelfDescribing, "\(kind) reads as itself and needs no label")
        }
        for kind in [ShareStatStickerKind.steps, .duration, .calories, .pace, .avgHeartRate,
                     .maxHeartRate, .verticalClimb, .addedWeight, .splits, .bestEffort, .totals] {
            #expect(!kind.isSelfDescribing, "\(kind) is a bare number and needs its unit")
        }
    }

    @Test
    func aDateRendersWithNoLabelAndAStepCountKeepsItsUnit() throws {
        let date = ResolvedShareStat(kind: .date, label: "DATE", value: "May 28, 2026")
        let steps = ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096")
        let context = ShareCardRenderContext(stats: [
            ShareStatRef(kind: .date): date,
            ShareStatRef(kind: .steps): steps
        ])

        #expect(context.label(for: Self.metric(.date)) == nil)
        #expect(context.label(for: Self.metric(.steps)) == "STEPS")
    }

    /// The exemption used to exist in exactly one of the two renderers, so a
    /// climb name alone had no label but the same climb name in a multi-metric
    /// sticker printed `LANDMARK`. One renderer, one answer.
    @Test
    func theExemptionHoldsWhateverElseIsOnTheSticker() throws {
        let climbName = ResolvedShareStat(kind: .climbName, label: "LANDMARK", value: "Empire State Building")
        let steps = ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096")
        let context = ShareCardRenderContext(stats: [
            ShareStatRef(kind: .climbName): climbName,
            ShareStatRef(kind: .steps): steps
        ])

        var sticker = ShareStickerInstance(kind: .climbName, labelPlacement: .below)
        sticker.extraStats = [ShareStatRef(kind: .steps)]
        let node = ShareStickerCardBuilder.node(for: sticker, resolvedRefs: sticker.statRefs)

        let labels = Self.labels(in: node, context: context)
        #expect(labels == [nil, "STEPS"], "the landmark keeps its exemption next to a labelled stat")
    }

    @Test
    func anExplicitPolicyOverridesTheStatsOwnClaim() {
        let date = ResolvedShareStat(kind: .date, label: "DATE", value: "May 28, 2026")
        let context = ShareCardRenderContext(stats: [ShareStatRef(kind: .date): date])

        #expect(context.label(for: Self.metric(.date, policy: .always)) == "DATE")
        #expect(context.label(for: Self.metric(.steps, policy: .never)) == nil)
    }

    /// `none` placement removes the label whatever the policy says, which is how
    /// the composer offers "no label" as a user choice.
    @Test
    func placementNoneSuppressesTheLabel() {
        let steps = ResolvedShareStat(kind: .steps, label: "STEPS", value: "2,096")
        let context = ShareCardRenderContext(stats: [ShareStatRef(kind: .steps): steps])

        #expect(context.label(for: Self.metric(.steps, placement: .none, policy: .always)) == nil)
    }

    /// A template may rename a label without touching the stat's own copy.
    @Test
    func aTemplateCanOverrideTheLabelCopy() {
        let heartRate = ResolvedShareStat(kind: .avgHeartRate, label: "AVG BPM", value: "131")
        let context = ShareCardRenderContext(stats: [ShareStatRef(kind: .avgHeartRate): heartRate])

        var metric = Self.metric(.avgHeartRate)
        metric.labelOverride = "AVG HR"
        #expect(context.label(for: metric) == "AVG HR")
    }

    // MARK: - Helpers

    static func metric(
        _ kind: ShareStatStickerKind,
        placement: ShareCardLabelPlacement = .below,
        policy: ShareCardLabelPolicy = .automatic
    ) -> ShareCardMetric {
        ShareCardMetric(
            stat: ShareStatRef(kind: kind),
            labelPlacement: placement,
            labelPolicy: policy,
            value: ShareCardTextStyle(size: 40),
            label: ShareCardTextStyle(size: 12)
        )
    }

    static func labels(in node: ShareCardNode, context: ShareCardRenderContext) -> [String?] {
        switch node.element {
        case .metric(let metric):
            return [context.label(for: metric)]
        case .stack(let stack):
            return stack.children.flatMap { labels(in: $0, context: context) }
        default:
            return []
        }
    }
}
