import SwiftUI

/// Percentile hero and distribution visualization for the Standing card.
struct ShareCardStandingView: View {
    let standing: ResolvedShareStanding
    let spec: ShareCardStandingSpec
    let context: ShareCardRenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero
            if !standing.isFirstAscent {
                distribution
            }
        }
        .frame(width: spec.width, height: spec.height, alignment: .topLeading)
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
                let progress = standing.isFirstAscent ? 0 : Double(standing.percentile) / 100
                let markerX = geometry.size.width * progress

                ZStack(alignment: .leading) {
                    ShareStandingCurve()
                        .fill(.white.opacity(0.16))

                    ShareStandingCurve()
                        .fill(Color(hex: "86D30A").opacity(0.72))
                        .frame(width: markerX)
                        .clipped()

                    if !standing.isFirstAscent {
                        Rectangle()
                            .fill(Color(hex: "86D30A"))
                            .frame(width: 2, height: 73)
                            .position(x: markerX, y: 50)
                            .overlay(alignment: .top) {
                                Text("YOU")
                                    .font(context.font.swiftUIFont(size: 8, role: .heavy))
                                    .tracking(1)
                                    .foregroundStyle(Color(hex: "86D30A"))
                                    .offset(x: markerX - geometry.size.width / 2, y: -4)
                            }
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
