import SwiftUI

/// The bell-curve stickers: where the climber stands on an idealised normal curve, for this climb
/// or for the week, month or year.
struct StickerBellCurveContent: View {
    private static let curveWidth: CGFloat = 130
    private static let curveHeight: CGFloat = 50
    /// The drawing is a little taller than the curve so the marker's dot has room below the baseline.
    private static let drawingHeight: CGFloat = 54
    private static let markerRadius: CGFloat = 3.5

    private struct Copy {
        let header: String
        let headline: String
        let footer: String
        /// The share of the field this finish beat, 0 to 1.
        let beaten: Double
    }

    private let copy: Copy
    private let geometry: BellCurveGeometry
    let ink: StickerInk

    init?(kind: StickerKind, subject: ShareSheetSubject?, totals: ShareTotalsSnapshot?, ink: StickerInk) {
        guard let copy = Self.resolveCopy(for: kind, subject: subject, totals: totals) else { return nil }
        self.copy = copy
        self.ink = ink
        geometry = BellCurveGeometry(
            percentile: copy.beaten,
            width: Double(Self.curveWidth),
            height: Double(Self.curveHeight)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ink.text(copy.header, size: 7, trackingEm: 0.18, opacity: 0.85)
            ink.text(copy.headline, size: 20, lineHeight: 1)
            curve
            ink.text(copy.footer, size: 8, trackingEm: 0.14, opacity: 0.9)
        }
    }

    private var curve: some View {
        let marker = geometry.marker
        return ZStack(alignment: .topLeading) {
            StickerPolylineShape(
                points: geometry.beatenPoints + [marker],
                closedToBaseline: Self.curveHeight
            )
            .fill(ink.color.opacity(0.35))
            StickerPolylineShape(points: geometry.outline)
                .stroke(ink.color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            StickerPolylineShape(points: [marker, CGPoint(x: marker.x, y: Self.curveHeight)])
                .stroke(ink.color, lineWidth: 1.5)
            Circle()
                .fill(ink.color)
                .frame(width: Self.markerRadius * 2, height: Self.markerRadius * 2)
                .offset(x: marker.x - Self.markerRadius, y: marker.y - Self.markerRadius)
        }
        .frame(width: Self.curveWidth, height: Self.drawingHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private static func resolveCopy(
        for kind: StickerKind,
        subject: ShareSheetSubject?,
        totals: ShareTotalsSnapshot?
    ) -> Copy? {
        switch kind {
        case .climbBellCurve:
            guard let subject, let rank = subject.rank else { return nil }
            return Copy(
                header: "VS. \(subject.stickerFieldName)",
                headline: rank.headline,
                footer: Self.footer(for: rank),
                beaten: Double(rank.field - rank.position) / Double(rank.field)
            )
        case .weeklyBellCurve:
            guard let standing = totals?.weekStanding else { return nil }
            return totalsCopy(header: "THIS WEEK", standing: standing)
        case .monthlyBellCurve:
            guard let totals, let standing = totals.monthStanding else { return nil }
            return totalsCopy(header: totals.calendarMonthName.uppercased(), standing: standing)
        case .yearlyBellCurve:
            guard let standing = totals?.yearStanding else { return nil }
            return totalsCopy(header: "\(StickerCalendarYear.current())", standing: standing)
        default:
            return nil
        }
    }

    /// The line under the curve: the rank is in the headline when the percentile is not, so it is
    /// only repeated here when the headline is `TOP 12%`.
    private static func footer(for rank: ShareSheetSubject.Rank) -> String {
        guard let beat = rank.beatCaption else { return rank.fieldCaption }
        let pool = "OF \(rank.fieldText)"
        return "\(rank.leadsWithPercent ? "#\(rank.positionText) " : "")\(pool) \u{00B7} \(beat)"
    }

    private static func totalsCopy(header: String, standing: ShareTotalsSnapshot.Standing) -> Copy {
        Copy(
            header: header,
            headline: standing.headline,
            footer: "\(standing.leadsWithPercent ? "\(standing.positionText) " : "")OF \(standing.fieldText) \u{00B7} BY STEPS",
            beaten: standing.beatFraction
        )
    }
}
