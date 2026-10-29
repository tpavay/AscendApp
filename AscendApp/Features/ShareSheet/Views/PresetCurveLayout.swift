import SwiftUI

/// Curve: the percentile headline over a bell curve with the climber's marker. The area the finish
/// beat is filled in the accent. Without a rank it falls back to the Classic body.
struct PresetCurveLayout: View {
    let model: PresetCardModel

    static let curveWidth: CGFloat = 270
    static let curveHeight: CGFloat = 120
    static let tagBoxWidth: CGFloat = 120
    /// The marker's dot is 9 points across and the tag's line about 12 tall.
    static let dotRadius: CGFloat = 4.5
    static let tagLineHeight: CGFloat = 12
    /// Above this height the tag no longer fits over the marker, so it moves beside it.
    private static let tagBesideBelow: Double = 20

    var body: some View {
        if let rank = model.subject.rank {
            content(rank: rank)
        } else {
            PresetClassicLayout(model: model)
        }
    }

    private func content(rank: ShareSheetSubject.Rank) -> some View {
        let palette = model.palette
        let axis = model.subject.rankAxis
        return VStack(alignment: .leading, spacing: 0) {
            Text(model.label)
                .presetText(model.font, size: 10, weight: 700, trackingEm: 0.2, color: Color(share: palette.secondary))
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
            PresetHeadlineLine(model: model, headline: rank.headline, caption: rank.fieldCaption)
                .padding(.top, 2)
            Spacer(minLength: 0)
            curve(rank: rank)
            HStack(spacing: 0) {
                Text(axis.lower)
                Spacer(minLength: 0)
                Text(rank.beatCaption ?? "").presetOneLine(floor: PresetFitGeometry.labelFloor)
                Spacer(minLength: 0)
                Text(axis.upper)
            }
            .presetText(model.font, size: 8, weight: 800, trackingEm: 0.14, color: Color(share: palette.secondary))
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func curve(rank: ShareSheetSubject.Rank) -> some View {
        let palette = model.palette
        let accent = Color(share: palette.accentText)
        let percentile = 1 - Double(rank.position) / Double(rank.field)
        let geometry = BellCurveGeometry(
            percentile: percentile,
            width: Double(Self.curveWidth),
            height: Double(Self.curveHeight)
        )
        let marker = geometry.marker
        let tag = Self.tag(markerX: marker.x, markerY: marker.y, isWide: rank.position >= 10_000)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: Self.curveHeight))
                for point in geometry.beatenPoints { path.addLine(to: point) }
                path.addLine(to: marker)
                path.addLine(to: CGPoint(x: marker.x, y: Self.curveHeight))
                path.closeSubpath()
            }
            .fill(accent.opacity(0.3))
            Path { path in
                guard let first = geometry.outline.first else { return }
                path.move(to: first)
                for point in geometry.outline.dropFirst() { path.addLine(to: point) }
            }
            .stroke(Color(share: palette.foreground).opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            Rectangle()
                .fill(Color(share: palette.rule))
                .frame(width: Self.curveWidth, height: 1)
                .offset(y: Self.curveHeight)
            Rectangle()
                .fill(accent)
                .frame(width: 2, height: max(Self.curveHeight - marker.y, 0))
                .offset(x: marker.x - 1, y: marker.y)
            Circle()
                .fill(accent)
                .frame(width: 9, height: 9)
                .offset(x: marker.x - 4.5, y: marker.y - 4.5)
            Text("YOU · #\(rank.positionText)")
                .presetText(model.font, size: 10, weight: 800, color: accent)
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
                .frame(width: Self.tagBoxWidth, alignment: tag.alignment)
                .position(x: marker.x + tag.boxOffset, y: tag.centerY)
        }
        .frame(width: Self.curveWidth, height: Self.curveHeight + 4, alignment: .topLeading)
    }

    /// Where the `YOU` tag sits: above the marker, flipping to a start or end anchor near an edge so
    /// it never leaves the curve's box. A marker near the top of the curve, which is where a finish
    /// in the middle of the field lands, has no room above it, so the tag moves beside it on the
    /// side the curve falls away from.
    /// A wide tag (a rank of five digits or more) is anchored to the low side of the marker instead
    /// of centred on it, because centred it reaches across the curve's rising or falling line.
    static func tag(markerX: Double, markerY: Double, isWide: Bool = false) -> (alignment: Alignment, boxOffset: CGFloat, centerY: CGFloat) {
        let width = Double(curveWidth)
        if markerY < tagBesideBelow {
            let gap = dotRadius + 6
            let centerY = CGFloat(markerY) - 1
            return markerX <= width / 2
                ? (.trailing, -(gap + tagBoxWidth / 2), centerY)
                : (.leading, gap + tagBoxWidth / 2, centerY)
        }
        // The design places the text baseline 10 units above the marker; a 10 point face centres
        // about 3.6 units above its baseline.
        let baseline = max(10, markerY - 10)
        let centerY = CGFloat(baseline - 3.6)
        if markerX > width - 30 {
            return (.trailing, -tagBoxWidth / 2, centerY)
        }
        if markerX < 30 {
            return (.leading, tagBoxWidth / 2, centerY)
        }
        if isWide {
            // The curve is lower on the outside of the peak, so the text sits there.
            return markerX <= width / 2
                ? (.trailing, -tagBoxWidth / 2 + 4, centerY)
                : (.leading, tagBoxWidth / 2 - 4, centerY)
        }
        return (.center, 0, centerY)
    }
}
