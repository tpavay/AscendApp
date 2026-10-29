import SwiftUI

/// Curve: the percentile headline over a bell curve with the climber's marker. The area the finish
/// beat is filled in the accent. Without a rank it falls back to the Classic body.
struct PresetCurveLayout: View {
    let model: PresetCardModel

    static let curveWidth: CGFloat = 270
    static let curveHeight: CGFloat = 120
    /// The marker's dot is 9 points across and the tag's line about 12 tall.
    static let dotRadius: CGFloat = 4.5
    static let tagLineHeight: CGFloat = 12
    /// A generous width per character of the tag's 10 point face, so the estimate is never short.
    static let tagCharacterWidth: CGFloat = 6.5
    /// Air kept between the tag's text and the curve's stroke or the marker's dot.
    private static let tagClearance: CGFloat = 2

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
        let tagText = Self.tagText(rank)
        let tag = Self.tagFrame(text: tagText, geometry: geometry)
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
            Text(tagText)
                .presetText(model.font, size: 10, weight: 800, color: accent)
                .presetOneLine(floor: PresetFitGeometry.labelFloor)
                .frame(width: tag.width, height: tag.height)
                .position(x: tag.midX, y: tag.midY)
        }
        .frame(width: Self.curveWidth, height: Self.curveHeight + 4, alignment: .topLeading)
    }

    static func tagText(_ rank: ShareSheetSubject.Rank) -> String {
        "YOU · #\(rank.positionText)"
    }

    /// Where the `YOU` tag's text sits in the curve's box: as close to the marker as it can be while
    /// staying wholly above the curve's outline, clear of the dot and inside the box. Near a tail the
    /// curve climbs toward the peak under the text, and at the peak it falls away on both sides, so
    /// no fixed offset from the marker clears it everywhere; every horizontal placement is tried and
    /// lifted until the outline under its whole width is below it.
    static func tagFrame(text: String, geometry: BellCurveGeometry) -> CGRect {
        let width = min(CGFloat(text.count) * tagCharacterWidth, curveWidth)
        let height = tagLineHeight
        let marker = geometry.marker
        let dot = CGRect(x: marker.x - dotRadius, y: marker.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            .insetBy(dx: -tagClearance, dy: -tagClearance)
        var best: (frame: CGRect, distance: CGFloat, drift: CGFloat)?
        var minX: CGFloat = 0
        while minX + width <= curveWidth {
            var bottom = lowestOutlineTop(geometry.outline, from: minX, to: minX + width) - tagClearance
            if minX < dot.maxX, minX + width > dot.minX {
                bottom = min(bottom, dot.minY)
            }
            let frame = CGRect(x: minX, y: bottom - height, width: width, height: height)
            if frame.minY >= 0 {
                let dx = max(frame.minX - marker.x, 0, marker.x - frame.maxX)
                let dy = max(frame.minY - marker.y, 0, marker.y - frame.maxY)
                let distance = (dx * dx + dy * dy).squareRoot()
                let drift = abs(frame.midX - marker.x)
                if best.map({ distance < $0.distance - 0.01 || (abs(distance - $0.distance) <= 0.01 && drift < $0.drift) }) ?? true {
                    best = (frame, distance, drift)
                }
            }
            minX += 1
        }
        return best?.frame ?? CGRect(x: 0, y: 0, width: width, height: height)
    }

    /// The smallest y (the highest point) the outline polyline reaches between two x positions.
    private static func lowestOutlineTop(_ outline: [CGPoint], from minX: CGFloat, to maxX: CGFloat) -> CGFloat {
        var top = CGFloat.infinity
        for (a, b) in zip(outline, outline.dropFirst()) where b.x >= minX && a.x <= maxX {
            let ends = [max(a.x, minX), min(b.x, maxX)].map { x in
                b.x == a.x ? min(a.y, b.y) : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
            }
            top = min(top, ends[0], ends[1])
        }
        return top
    }
}
