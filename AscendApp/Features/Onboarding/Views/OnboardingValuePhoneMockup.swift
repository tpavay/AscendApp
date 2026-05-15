import SwiftUI

struct OnboardingValuePhoneMockup: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    let imageName: String
    var scale: CGFloat = 1
    var xOffset: CGFloat = 0
    var yOffset: CGFloat = 0
    var rotation: Angle = .degrees(-1.5)
    var perspectiveRotation: Angle = .degrees(-3)
    var enablesFloating: Bool = true

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .rotation3DEffect(
                perspectiveRotation,
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.58
            )
            .rotationEffect(rotation)
            .offset(
                x: xOffset,
                y: yOffset + floatingOffset
            )
            .shadow(color: .black.opacity(0.78), radius: 32, x: 0, y: 24)
            .shadow(color: OnboardingValuePalette.lime.opacity(0.16), radius: 28, x: 0, y: 0)
            .background {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                OnboardingValuePalette.lime.opacity(0.18),
                                Color(red: 0.05, green: 0.33, blue: 0.42).opacity(0.16),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 190
                        )
                    )
                    .frame(width: 280, height: 430)
                    .blur(radius: 38)
                    .offset(y: 24)
            }
            .task {
                startFloatingAnimationIfNeeded()
            }
    }

    private var floatingOffset: CGFloat {
        guard enablesFloating, !reduceMotion else { return 0 }
        return isFloating ? -6 : 4
    }

    private func startFloatingAnimationIfNeeded() {
        guard enablesFloating, !reduceMotion else { return }

        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
            isFloating = true
        }
    }
}
