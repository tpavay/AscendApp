import SwiftUI

/// Percentile hero and distribution visualization for the Standing card.
struct ShareCardStandingView: View {
    let standing: ResolvedShareStanding
    let spec: ShareCardStandingSpec
    let context: ShareCardRenderContext

    /// Half the rendered width of the "YOU" caption, used to keep it inside the
    /// plot when the marker sits against either edge.
    private static let labelHalfWidth: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero
            if !standing.isFirstAscent {
                distribution
            }
        }
        .frame(width: spec.width, height: spec.height.map { CGFloat($0) }, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var hero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 15) {
            Text(standing.isFirstAscent ? "1st" : "\(standing.percentile)%")
                .font(context.font.swiftUIFont(size: 78, role: .heavy))
                .foregroundStyle(Color(hex: "86D30A"))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(
                standing.isFirstAscent
                    ? "NOBODY HAS CLIMBED THIS\nTOWER BEFORE YOU"
                    : "FASTER THAN \(standing.percentile)% OF\n\(standing.formattedFieldSize) CLIMBERS"
            )
            .font(context.font.swiftUIFont(size: 10, role: .heavy))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.82))
            .lineSpacing(3)
            .padding(.bottom, 9)
        }
    }

    private var distribution: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let markerX: CGFloat = width * CGFloat(standing.percentile) / 100

                ZStack(alignment: .leading) {
                    ShareStandingCurve()
                        .fill(.white.opacity(0.16))

                    // Masked rather than framed: a `Shape` lays its path out in
                    // the rect it is given, so framing to the marker would
                    // squeeze the whole bell curve instead of revealing the
                    // share of the field this climber actually beat.
                    ShareStandingCurve()
                        .fill(Color(hex: "86D30A").opacity(0.72))
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: markerX)
                        }

                    Rectangle()
                        .fill(Color(hex: "86D30A"))
                        .frame(width: 2, height: 73)
                        .position(x: min(max(markerX, 1), width - 1), y: 50)
                        .overlay(alignment: .top) {
                            Text("YOU")
                                .font(context.font.swiftUIFont(size: 8, role: .heavy))
                                .tracking(1)
                                .foregroundStyle(Color(hex: "86D30A"))
                                // Kept inside the plot at both extremes, where
                                // the marker itself sits on the edge.
                                .offset(
                                    x: min(max(markerX, Self.labelHalfWidth), width - Self.labelHalfWidth)
                                        - width / 2,
                                    y: -4
                                )
                        }
                }
            }
            .frame(height: 104)

            HStack {
                Text("SLOWER")
                Spacer()
                Text("FASTER")
            }
            .font(context.font.swiftUIFont(size: 8, role: .medium))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var accessibilityText: String {
        if standing.isFirstAscent {
            return "First Ascent. Nobody has climbed this tower before you."
        }
        return "Faster than \(standing.percentile) percent of \(standing.formattedFieldSize) climbers."
    }
}

private struct ShareStandingCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        for sample in 0...80 {
            let fraction = CGFloat(sample) / 80
            let centered = (fraction - 0.5) / 0.19
            let density = exp(-0.5 * centered * centered)
            path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.maxY - density * rect.height * 0.88))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
