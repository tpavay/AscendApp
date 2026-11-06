import SwiftUI

/// The gold "#1 IN YOUR CITY" medallion: spinning rays behind a dark disc, a crown bobbing on its
/// rim. Reduce Motion keeps it still.
struct CityBadge: View {
    let kicker: String
    let place: String
    let pill: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    private let diameter: CGFloat = 232

    var body: some View {
        ZStack {
            rays
                .rotationEffect(.degrees(isAnimating && !reduceMotion ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 14).repeatForever(autoreverses: false), value: isAnimating)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [OnboardingV3Palette.gold.opacity(0.2), Color(hex: "0A0A0A")],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: diameter
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(OnboardingV3Palette.gold, lineWidth: 4))

            VStack(spacing: 8) {
                Text(kicker)
                    .font(.custom("Montserrat-Black", size: 15))
                    .tracking(3)
                    .foregroundStyle(OnboardingV3Palette.gold)

                Text(place)
                    .font(.custom("Montserrat-Black", size: 30))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.45)
                    .multilineTextAlignment(.center)

                Text(pill)
                    .font(.custom("Montserrat-Black", size: 13))
                    .tracking(2.4)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(OnboardingV3Palette.gold))
            }
            .padding(.horizontal, 30)
            .frame(width: diameter)

            CityCrownShape()
                .fill(OnboardingV3Palette.gold)
                .frame(width: 70, height: 52)
                .rotationEffect(.degrees(12))
                .offset(x: 62, y: -(diameter / 2) + 8 + (isAnimating && !reduceMotion ? -5 : 0))
                .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: isAnimating)
        }
        .frame(width: diameter + 60, height: diameter + 60)
        .onAppear { isAnimating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kicker) \(place), \(pill)")
    }

    private var rays: some View {
        ZStack {
            ForEach(0..<28, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(OnboardingV3Palette.gold.opacity(index.isMultiple(of: 2) ? 0.2 : 0.1))
                    .frame(width: 8, height: 30)
                    .offset(y: -(diameter / 2 + 12))
                    .rotationEffect(.degrees(Double(index) * 360 / 28))
            }
        }
    }
}

/// A five-point crown on a flat band.
struct CityCrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width, height = rect.height
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: height * 0.28))
        path.addLine(to: CGPoint(x: width * 0.24, y: height * 0.58))
        path.addLine(to: CGPoint(x: width * 0.5, y: 0))
        path.addLine(to: CGPoint(x: width * 0.76, y: height * 0.58))
        path.addLine(to: CGPoint(x: width, y: height * 0.28))
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        return path
    }
}

#Preview("City badge") {
    CityBadge(kicker: "#1 IN", place: "YOUR CITY", pill: "OPEN")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}
