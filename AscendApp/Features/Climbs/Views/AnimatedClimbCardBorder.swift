import SwiftUI

struct AnimatedClimbCardBorder: ViewModifier {
    let colors: [Color]
    let shadowColor: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateGradient = false
    @State private var pulseShadow = false

    func body(content: Content) -> some View {
        content
            .overlay(borderOverlay)
            .shadow(
                color: shadowColor.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: 0
            )
            .onAppear {
                guard !reduceMotion else { return }

                withAnimation(.linear(duration: 5.6).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }

                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    pulseShadow = true
                }
            }
    }

    private var shadowOpacity: Double {
        if reduceMotion {
            return 0.05
        }

        return pulseShadow ? 0.12 : 0.05
    }

    private var shadowRadius: CGFloat {
        if reduceMotion {
            return 6
        }

        return pulseShadow ? 10 : 6
    }

    private var gradientStartPoint: UnitPoint {
        animateGradient ? .bottomTrailing : .topLeading
    }

    private var gradientEndPoint: UnitPoint {
        animateGradient ? .topLeading : .bottomTrailing
    }

    private var resolvedColors: [Color] {
        let baseColors = colors.isEmpty ? [.white.opacity(0.2)] : colors

        if baseColors.count == 1 {
            let color = baseColors[0]
            return [color.opacity(0.08), color.opacity(0.45), color.opacity(0.14)]
        }

        return [
            baseColors[0].opacity(0.1),
            baseColors[0].opacity(0.34),
            baseColors[1].opacity(0.72),
            baseColors[1].opacity(0.12)
        ]
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: resolvedColors,
                    startPoint: gradientStartPoint,
                    endPoint: gradientEndPoint
                ),
                lineWidth: lineWidth
            )
    }
}

extension View {
    func animatedClimbCardBorder(
        colors: [Color],
        shadowColor: Color,
        cornerRadius: CGFloat = 28,
        lineWidth: CGFloat = 1.5
    ) -> some View {
        modifier(
            AnimatedClimbCardBorder(
                colors: colors,
                shadowColor: shadowColor,
                cornerRadius: cornerRadius,
                lineWidth: lineWidth
            )
        )
    }
}
