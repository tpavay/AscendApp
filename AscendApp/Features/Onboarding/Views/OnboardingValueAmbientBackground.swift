import SwiftUI

struct OnboardingValueAmbientBackground: View {
    enum Style {
        case tracking
        case leaderboards
        case progress
    }

    let style: Style

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                RadialGradient(
                    colors: [
                        primaryGlow.opacity(0.36),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 24,
                    endRadius: geometry.size.height * 0.72
                )

                RadialGradient(
                    colors: [
                        secondaryGlow.opacity(0.32),
                        .clear
                    ],
                    center: .bottomLeading,
                    startRadius: 12,
                    endRadius: geometry.size.height * 0.66
                )

                treatment
                    .opacity(0.74)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.26),
                        .clear,
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay {
                OnboardingValueAmbientNoise()
                    .opacity(0.28)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var treatment: some View {
        switch style {
        case .tracking:
            OnboardingTrackingLightField()
        case .leaderboards:
            OnboardingMotionStreakField()
        case .progress:
            OnboardingProgressGlowField()
        }
    }

    private var primaryGlow: Color {
        switch style {
        case .tracking:
            Color(red: 0.1, green: 0.46, blue: 0.7)
        case .leaderboards:
            OnboardingValuePalette.lime
        case .progress:
            Color(red: 0.0, green: 0.58, blue: 0.52)
        }
    }

    private var secondaryGlow: Color {
        switch style {
        case .tracking:
            OnboardingValuePalette.lime
        case .leaderboards:
            Color(red: 0.86, green: 0.45, blue: 0.08)
        case .progress:
            OnboardingValuePalette.lime
        }
    }
}

private struct OnboardingTrackingLightField: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<5 {
                let center = CGPoint(
                    x: size.width * (0.18 + CGFloat(index) * 0.18),
                    y: size.height * (0.22 + CGFloat(index % 2) * 0.12)
                )
                let radius = size.width * (0.2 + CGFloat(index) * 0.02)
                let rect = CGRect(
                    x: center.x - radius / 2,
                    y: center.y - radius / 2,
                    width: radius,
                    height: radius
                )

                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(index == 2 ? 0.055 : 0.025))
                )
            }
        }
        .blur(radius: 18)
    }
}

private struct OnboardingMotionStreakField: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<18 {
                let y = size.height * (0.12 + CGFloat(index) * 0.045)
                var path = Path()
                path.move(to: CGPoint(x: -size.width * 0.18, y: y))
                path.addLine(to: CGPoint(x: size.width * 1.18, y: y - size.height * 0.18))

                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            .clear,
                            .white.opacity(index % 4 == 0 ? 0.18 : 0.07),
                            OnboardingValuePalette.lime.opacity(index % 3 == 0 ? 0.18 : 0.08),
                            .clear
                        ]),
                        startPoint: CGPoint(x: 0, y: y),
                        endPoint: CGPoint(x: size.width, y: y - size.height * 0.16)
                    ),
                    lineWidth: index % 4 == 0 ? 1.15 : 0.65
                )
            }
        }
        .blur(radius: 0.35)
    }
}

private struct OnboardingProgressGlowField: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<4 {
                var path = Path()
                let baseY = size.height * (0.26 + CGFloat(index) * 0.11)
                path.move(to: CGPoint(x: -20, y: baseY))

                for step in 0...7 {
                    let x = size.width * CGFloat(step) / 7
                    let wave = sin(CGFloat(step) * 0.9 + CGFloat(index)) * size.height * 0.035
                    path.addLine(to: CGPoint(x: x, y: baseY - CGFloat(step) * 11 + wave))
                }

                context.stroke(
                    path,
                    with: .color(index == 0 ? OnboardingValuePalette.lime.opacity(0.2) : .white.opacity(0.08)),
                    lineWidth: index == 0 ? 1.2 : 0.7
                )
            }
        }
        .blur(radius: 0.45)
    }
}

private struct OnboardingValueAmbientNoise: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<96 {
                let x = size.width * CGFloat((index * 29 + 7) % 89) / 88
                let y = size.height * CGFloat((index * 47 + 17) % 97) / 96
                let rect = CGRect(x: x, y: y, width: 0.8, height: 0.8)

                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(0.035))
                )
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
