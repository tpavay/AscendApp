import Foundation

/// A pre-formatted group of stats a climber drops onto any background and moves
/// as one unit.
///
/// The app already ships individual stat stickers; a preset is the arrangement
/// done for them, so nobody has to lay stats out by hand and nobody is pushed
/// onto one of the finalized recap cards just to use their own photo. It is
/// curated data on top of the existing sticker system, not a second one: the
/// tree is the same `ShareCardNode` format a template is written in, drawn by
/// the same interpreter, tinted by the same render context, and placed as an
/// ordinary `ShareStickerInstance`.
///
/// Two rules the composer relies on:
/// - **Plate-free.** A preset carries no backing panel; it stays legible over a
///   photograph on its shadow alone. The edit rail's existing text-background
///   control is how a climber adds one when their photo is busy.
/// - **Availability follows the data.** `requires` names the stats without which
///   the arrangement is hollow. A preset whose required stats do not resolve is
///   never offered - which is why the same catalog serves a Live Climb, a
///   routine and a Just Climb without ever branding a preset by session type.
struct ShareStatClusterPreset: Identifiable, Sendable {
    let id: String
    /// Name shown on the add sheet's tile.
    let title: String
    /// The face the cluster is designed in. The climber can still switch to any
    /// of the six from the edit rail; this is only where it starts.
    let font: ShareStickerFont
    /// Stats without which this arrangement is not worth offering.
    let requires: [ShareStatRef]
    /// Every stat the cluster can draw. A stat outside `requires` that does not
    /// resolve simply drops its cell, exactly as it would on any other card.
    let stats: [ShareStatRef]
    /// The cluster itself, plate-free. `ShareStickerCardBuilder` wraps it in the
    /// climber's chosen text background.
    let content: ShareCardNode

    /// The split tables this cluster's tree actually draws.
    ///
    /// Read off the tree rather than declared beside it, because the two would
    /// drift: a `.splits` stat resolves off the pace timeline, while a step-range
    /// table is built from a different array that a short session leaves empty.
    /// Availability asks this so a preset cannot be offered an arrangement whose
    /// rows it has nothing to fill.
    var splitLayouts: Set<ShareCardSplitsLayout> {
        Self.splitLayouts(in: content)
    }

    private static func splitLayouts(in node: ShareCardNode) -> Set<ShareCardSplitsLayout> {
        switch node.element {
        case .splits(let spec):
            return [spec.layout]
        case .stack(let stack):
            return stack.children.reduce(into: []) { $0.formUnion(splitLayouts(in: $1)) }
        default:
            return []
        }
    }
}

/// The approved clusters.
///
/// Sizes are the design review's own pixel values put through `Design.u`, so the
/// approved page stays the readable specification: a number here can be checked
/// against the mock without arithmetic. The settled rules a cluster has to keep
/// are `docs/share-stat-clusters.md`.
///
/// That page is not in this repository. It is `.lavish/ascend-stat-clusters.html`
/// revision 6, next to `data/ascend-summary-and-share-design.md`, both in the
/// firstmate home. Every size below is still the mock's own pixel value through
/// `Design.u`, so the catalog can be verified against the numbers without it.
enum ShareStatClusterPresets {
    static let all: [ShareStatClusterPreset] = [
        hero, rank, row, splits, receipt, minimal, routine,
        heartRateHero, heartRateRow, fullGrid, heartRateMinimal
    ]

    static func preset(id: String) -> ShareStatClusterPreset? {
        all.first { $0.id == id }
    }

    // MARK: - The seven

    /// Tower name, finish time large, then steps / pace / floors.
    private static let hero = ShareStatClusterPreset(
        id: "hero",
        title: "Hero",
        font: .anton,
        requires: [ref(.climbName), ref(.duration)],
        stats: [ref(.climbName), ref(.duration), ref(.steps), ref(.pace), ref(.climbFloors)],
        content: column([
            title(ref(.climbName), width: 118),
            metric(ref(.duration), size: 52, labelOverride: "FINISH TIME", labelOpacity: 0.5, topPadding: 6),
            rule(width: 118),
            statRow([
                metric(ref(.steps), size: 15),
                metric(ref(.pace), size: 15),
                metric(ref(.climbFloors), size: 15)
            ])
        ])
    )

    /// Rank very large, of-field and tower beneath, then time and pace.
    private static let rank = ShareStatClusterPreset(
        id: "rank",
        title: "Rank",
        font: .anton,
        requires: [ref(.climbRank), ref(.climbRankWithTotal), ref(.climbName)],
        stats: [ref(.climbRank), ref(.climbRankWithTotal), ref(.climbName), ref(.duration), ref(.pace)],
        content: column([
            // The ordinal, not the `#4` sigil: at this size the rank is the
            // headline rather than a field in a table.
            text([segment(ref(.climbRank), facet: .detail)], style: value(60)),
            text(
                [literal("OF "), segment(ref(.climbRankWithTotal), facet: .detail),
                 literal(" · "), segment(ref(.climbName))],
                style: caption(),
                uppercased: true,
                width: 115,
                topPadding: 4
            ),
            rule(width: 115),
            statRow([
                metric(ref(.duration), size: 15, labelOverride: "TIME"),
                metric(ref(.pace), size: 15)
            ])
        ])
    )

    /// Time, steps and pace side by side.
    private static let row = ShareStatClusterPreset(
        id: "row",
        title: "Row",
        font: .montserrat,
        requires: [ref(.duration), ref(.steps), ref(.pace)],
        stats: [ref(.duration), ref(.steps), ref(.pace)],
        content: statRow([
            metric(ref(.duration), size: 20, labelOverride: "TIME"),
            metric(ref(.steps), size: 20),
            metric(ref(.pace), size: 20)
        ])
    )

    /// Five step-range rows with their bars and elapsed times - the Result
    /// card's own table - then time and average.
    private static let splits = ShareStatClusterPreset(
        id: "splits",
        title: "Splits",
        font: .montserrat,
        requires: [ref(.splits), ref(.duration)],
        stats: [ref(.splits), ref(.duration), ref(.pace)],
        content: column(alignment: .leading, [
            title(literalText: "SPLITS BY STEP"),
            ShareCardNode(
                .splits(ShareCardSplitsTableSpec(
                    layout: .stepQuintiles,
                    width: Design.u(196),
                    baseSize: Design.u(14.5),
                    // The cluster writes its own heading and needs no legend:
                    // this is a sticker over a photograph, not a full card.
                    showsTitle: false,
                    showsHeader: false,
                    textTint: ShareCardTint(.value),
                    fastTint: ShareCardTint(.value),
                    slowTint: ShareCardTint(.value, opacity: 0.42),
                    trackTint: ShareCardTint(.value, opacity: 0.16),
                    legibility: .outline
                )),
                modifiers: ShareCardModifiers(padding: ShareCardEdgeInsets(top: Design.u(9)))
            ),
            rule(width: 196),
            statRow([
                metric(ref(.duration), size: 15, labelOverride: "TIME", alignment: .leading),
                metric(ref(.pace), size: 15, labelOverride: "AVG SPM", alignment: .leading)
            ])
        ])
    )

    /// A dated ticket: rank and tower over the three stats, in a monospace face.
    private static let receipt = ShareStatClusterPreset(
        id: "receipt",
        title: "Receipt",
        font: .spaceMono,
        requires: [ref(.date), ref(.climbName), ref(.duration)],
        stats: [ref(.date), ref(.climbName), ref(.climbRankWithTotal),
                ref(.duration), ref(.steps), ref(.pace)],
        content: column(alignment: .leading, [
            ShareCardNode(
                .stack(ShareCardStack(
                    axis: .horizontal,
                    spacing: Design.u(8),
                    alignment: .center,
                    children: [
                        text([segment(ref(.date), facet: .detail)], style: caption(opacity: 0.55, tracking: 0.14)),
                        ShareCardNode(.spacer(minLength: nil)),
                        text(
                            [literal("RANK "), segment(ref(.climbRankWithTotal))],
                            style: caption(opacity: 0.55, tracking: 0.14)
                        )
                    ]
                )),
                modifiers: ShareCardModifiers(frame: ShareCardFrame(width: Design.u(190)))
            ),
            rule(width: 190),
            text(
                [segment(ref(.climbName))],
                style: value(17, alignment: .leading),
                uppercased: true,
                width: 190,
                alignment: .leading
            ),
            statRow(topPadding: 9, [
                metric(ref(.duration), size: 14, labelOverride: "TIME", alignment: .leading),
                metric(ref(.steps), size: 14, alignment: .leading),
                metric(ref(.pace), size: 14, alignment: .leading)
            ])
        ])
    )

    /// One large number with its own label, and the context on a separate line.
    private static let minimal = ShareStatClusterPreset(
        id: "minimal",
        title: "Minimal",
        font: .montserrat,
        requires: [ref(.steps)],
        stats: [ref(.steps), ref(.climbName), ref(.duration)],
        content: column([
            metric(ref(.steps), size: 46, labelOverride: "STEPS CLIMBED", labelOpacity: 0.8, spacing: 3),
            // A climb names its tower; anything else has only the clock, so the
            // line shortens rather than disappearing.
            text(
                [segment(ref(.climbName)), literal(" · "), segment(ref(.duration))],
                fallback: [segment(ref(.duration))],
                style: caption(opacity: 0.5),
                uppercased: true,
                width: 150,
                topPadding: 8
            )
        ])
    )

    /// Routine name, session time, then steps / pace / intervals.
    private static let routine = ShareStatClusterPreset(
        id: "routine",
        title: "Routine",
        font: .montserrat,
        requires: [ref(.workoutName), ref(.duration), ref(.routineIntervals)],
        stats: [ref(.workoutName), ref(.duration), ref(.steps), ref(.pace), ref(.routineIntervals)],
        content: column([
            text(
                [literal("ROUTINE · "), segment(ref(.workoutName))],
                style: caption(),
                uppercased: true,
                width: 118
            ),
            metric(ref(.duration), size: 40, labelPlacement: .none, topPadding: 6),
            statRow(topPadding: 8, [
                metric(ref(.steps), size: 15),
                metric(ref(.pace), size: 15),
                metric(ref(.routineIntervals), size: 15)
            ])
        ])
    )

    // MARK: - Heart rate
    //
    // Only two heart-rate numbers exist per workout, average and peak, so these
    // are stickers rather than a trace. The labels are standardized - AVERAGE HR
    // and MAX HR, no BPM suffix and no heart glyph - and the resolver owns that
    // copy, so every heart-rate sticker reads the same wherever it appears.

    /// Average large, max centered beneath it, then time and steps.
    private static let heartRateHero = ShareStatClusterPreset(
        id: "hr-hero",
        title: "HR Hero",
        font: .anton,
        requires: [ref(.avgHeartRate), ref(.maxHeartRate)],
        stats: [ref(.avgHeartRate), ref(.maxHeartRate), ref(.duration), ref(.steps)],
        content: column([
            title(literalText: "AVERAGE HR"),
            metric(ref(.avgHeartRate), size: 56, labelPlacement: .none, topPadding: 6),
            metric(ref(.maxHeartRate), size: 7, labelPlacement: .leading,
                   labelOpacity: 0.5, valueOpacity: 0.5, spacing: 4, topPadding: 4),
            rule(width: 96),
            statRow([
                metric(ref(.duration), size: 15, labelOverride: "TIME"),
                metric(ref(.steps), size: 15)
            ])
        ])
    )

    /// Time, average and max side by side.
    private static let heartRateRow = ShareStatClusterPreset(
        id: "hr-row",
        title: "HR Row",
        font: .montserrat,
        requires: [ref(.avgHeartRate), ref(.maxHeartRate), ref(.duration)],
        stats: [ref(.duration), ref(.avgHeartRate), ref(.maxHeartRate)],
        content: statRow([
            metric(ref(.duration), size: 20, labelOverride: "TIME"),
            metric(ref(.avgHeartRate), size: 20),
            metric(ref(.maxHeartRate), size: 20)
        ])
    )

    /// Tower name over a 2×2 of time, steps, average and max.
    private static let fullGrid = ShareStatClusterPreset(
        id: "full-grid",
        title: "Full Grid",
        font: .montserrat,
        requires: [ref(.climbName), ref(.avgHeartRate), ref(.maxHeartRate)],
        stats: [ref(.climbName), ref(.duration), ref(.steps), ref(.avgHeartRate), ref(.maxHeartRate)],
        content: column(alignment: .leading, [
            title(ref(.climbName), width: 178, alignment: .leading),
            ShareCardNode(
                .stack(ShareCardStack(
                    axis: .vertical,
                    spacing: Design.u(18),
                    alignment: .leading,
                    gridColumns: 2,
                    rowSpacing: Design.u(12),
                    children: [
                        // A fixed cell width is what lines the two columns up;
                        // self-sizing cells would stagger `18:42` against `148`.
                        metric(ref(.duration), size: 18, labelOverride: "TIME", alignment: .leading, width: 80),
                        metric(ref(.steps), size: 18, alignment: .leading, width: 80),
                        metric(ref(.avgHeartRate), size: 18, alignment: .leading, width: 80),
                        metric(ref(.maxHeartRate), size: 18, alignment: .leading, width: 80)
                    ]
                )),
                modifiers: ShareCardModifiers(padding: ShareCardEdgeInsets(top: Design.u(9)))
            )
        ])
    )

    /// The average alone, with max beneath it.
    private static let heartRateMinimal = ShareStatClusterPreset(
        id: "hr-minimal",
        title: "HR Minimal",
        font: .montserrat,
        requires: [ref(.avgHeartRate), ref(.maxHeartRate)],
        stats: [ref(.avgHeartRate), ref(.maxHeartRate)],
        content: column([
            metric(ref(.avgHeartRate), size: 44, labelOpacity: 0.8, spacing: 3),
            metric(ref(.maxHeartRate), size: 7, labelPlacement: .leading,
                   labelOpacity: 0.5, valueOpacity: 0.5, spacing: 4, topPadding: 7)
        ])
    )

    // MARK: - Design vocabulary

    /// The approved review page draws clusters on a 236pt-wide phone; the card
    /// format's design space is 390 wide. Every size in this file is the mock's
    /// own pixel value put through here.
    private enum Design {
        static let scale = 390.0 / 236.0
        static func u(_ mockPixels: Double) -> Double { mockPixels * scale }
    }

    private static func ref(_ kind: ShareStatStickerKind) -> ShareStatRef {
        ShareStatRef(kind: kind)
    }

    private static func literal(_ text: String) -> ShareCardTextSegment {
        ShareCardTextSegment(literal: text)
    }

    private static func segment(
        _ ref: ShareStatRef,
        facet: ShareCardStatFacet = .value
    ) -> ShareCardTextSegment {
        ShareCardTextSegment(stat: ref, facet: facet)
    }

    /// The small tracked-out caption every cluster labels with. White at reduced
    /// opacity rather than the lime accent, because a cluster sits on a
    /// photograph where the accent fights the image.
    private static func caption(
        _ mockSize: Double = 7,
        opacity: Double = 0.6,
        tracking: Double = 0.2
    ) -> ShareCardTextStyle {
        let size = Design.u(mockSize)
        return ShareCardTextStyle(
            role: .heavy,
            size: size,
            tracking: size * tracking,
            tint: ShareCardTint(.value, opacity: opacity),
            lineLimit: 1,
            // Towers are not all called Taipei 101. Inside a bounded cluster a
            // long landmark shrinks to fit rather than dragging the whole
            // arrangement wider than it was designed to be.
            minimumScaleFactor: 0.5,
            legibility: legibility(at: size)
        )
    }

    private static func value(
        _ mockSize: Double,
        opacity: Double = 1,
        alignment: ShareCardTextAlignment? = nil
    ) -> ShareCardTextStyle {
        let size = Design.u(mockSize)
        return ShareCardTextStyle(
            role: .heavy,
            size: size,
            tint: ShareCardTint(.value, opacity: opacity),
            lineLimit: 1,
            minimumScaleFactor: 0.5,
            alignment: alignment,
            legibility: legibility(at: size)
        )
    }

    /// A cluster is bare text over somebody's photograph, so every run carries a
    /// treatment - the question is only which.
    ///
    /// Below this size the run is a tracked-out cap a few pixels thick, and
    /// against snow or a blown-out sky a drop shadow alone leaves it washed out;
    /// it takes the outline as well. Above it, a number has ink enough that the
    /// outline would only thicken the face.
    /// The one number behind that split, so the catalog, the tests and the skill
    /// cannot each carry their own answer to where the outline starts.
    static let outlineBelow = Design.u(14)

    private static func legibility(at size: Double) -> ShareCardTextLegibility {
        size < outlineBelow ? .outline : .shadow
    }

    // MARK: - Node vocabulary

    private static func column(
        alignment: ShareCardAlignment = .center,
        _ children: [ShareCardNode]
    ) -> ShareCardNode {
        ShareCardNode(.stack(ShareCardStack(axis: .vertical, spacing: 0, alignment: alignment, children: children)))
    }

    /// A row of stats. Where it sits across the cluster is the enclosing
    /// column's alignment, not the row's own - a left-aligned cluster's rows
    /// start at the same edge as its heading because the column says so.
    private static func statRow(
        topPadding: Double = 0,
        _ children: [ShareCardNode]
    ) -> ShareCardNode {
        ShareCardNode(
            .stack(ShareCardStack(
                axis: .horizontal,
                spacing: Design.u(16),
                alignment: .top,
                children: children
            )),
            modifiers: topPadding == 0
                ? ShareCardModifiers()
                : ShareCardModifiers(padding: ShareCardEdgeInsets(top: Design.u(topPadding)))
        )
    }

    /// A cluster's heading: either a stat's own value (a tower name) or fixed
    /// copy (`SPLITS BY STEP`).
    private static func title(
        _ ref: ShareStatRef,
        width mockWidth: Double,
        alignment: ShareCardAlignment = .center
    ) -> ShareCardNode {
        text([segment(ref)], style: caption(), uppercased: true, width: mockWidth, alignment: alignment)
    }

    private static func title(literalText: String) -> ShareCardNode {
        text([literal(literalText)], style: caption())
    }

    /// `width` is what gives `minimumScaleFactor` something to shrink into: a
    /// run with no bound simply grows, and a landmark long enough to do that
    /// pushes the cluster past the rule underneath it.
    private static func text(
        _ segments: [ShareCardTextSegment],
        fallback: [ShareCardTextSegment]? = nil,
        style: ShareCardTextStyle,
        uppercased: Bool = false,
        width mockWidth: Double? = nil,
        alignment: ShareCardAlignment = .center,
        topPadding: Double = 0
    ) -> ShareCardNode {
        var modifiers = ShareCardModifiers()
        if topPadding != 0 {
            modifiers.padding = ShareCardEdgeInsets(top: Design.u(topPadding))
        }
        if let mockWidth {
            modifiers.frame = ShareCardFrame(width: Design.u(mockWidth), alignment: alignment)
        }
        return ShareCardNode(
            .text(ShareCardText(
                segments: segments,
                fallback: fallback,
                style: style,
                transform: uppercased ? .uppercase : .none
            )),
            modifiers: modifiers
        )
    }

    /// One stat drawn as a value with the cluster's caption beneath it.
    private static func metric(
        _ ref: ShareStatRef,
        size mockSize: Double,
        labelPlacement: ShareCardLabelPlacement = .below,
        labelOverride: String? = nil,
        labelOpacity: Double = 0.6,
        valueOpacity: Double = 1,
        alignment: ShareCardAlignment = .center,
        spacing: Double = 2,
        width: Double? = nil,
        topPadding: Double = 0
    ) -> ShareCardNode {
        var modifiers = ShareCardModifiers()
        if topPadding != 0 {
            modifiers.padding = ShareCardEdgeInsets(top: Design.u(topPadding))
        }
        if let width {
            modifiers.frame = ShareCardFrame(width: Design.u(width), alignment: alignment)
        }
        return ShareCardNode(
            .metric(ShareCardMetric(
                stat: ref,
                labelPlacement: labelPlacement,
                labelPolicy: .automatic,
                labelOverride: labelOverride,
                value: value(mockSize, opacity: valueOpacity, alignment: alignment.textAlignment),
                label: caption(opacity: labelOpacity),
                spacing: Design.u(spacing),
                alignment: alignment
            )),
            modifiers: modifiers
        )
    }

    /// The hairline between a cluster's headline and its stat row. It spans the
    /// cluster, so it carries the width the mock's widest row settles at rather
    /// than collapsing to a flexible view's ideal size inside `fixedSize()`.
    private static func rule(width mockWidth: Double) -> ShareCardNode {
        ShareCardNode(
            .rule(ShareCardRule(thickness: 1, tint: ShareCardTint(.value, opacity: 0.22))),
            modifiers: ShareCardModifiers(
                padding: ShareCardEdgeInsets(top: Design.u(10), bottom: Design.u(10)),
                frame: ShareCardFrame(width: Design.u(mockWidth))
            )
        )
    }
}

private extension ShareCardAlignment {
    var textAlignment: ShareCardTextAlignment? {
        switch self {
        case .leading, .topLeading, .bottomLeading: return .leading
        case .trailing, .topTrailing, .bottomTrailing: return .trailing
        default: return .center
        }
    }
}
