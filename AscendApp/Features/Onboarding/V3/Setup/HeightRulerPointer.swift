import SwiftUI

/// The fixed pointer across the ruler's middle: a lime line with a small triangle on its left end.
struct HeightRulerPointer: View {
    var body: some View {
        HStack(spacing: 0) {
            Triangle()
                .fill(OnboardingV3Palette.accent)
                .frame(width: 10, height: 14)

            Capsule()
                .fill(OnboardingV3Palette.accent)
                .frame(height: 3)
                .shadow(color: OnboardingV3Palette.accent.opacity(0.55), radius: 6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
