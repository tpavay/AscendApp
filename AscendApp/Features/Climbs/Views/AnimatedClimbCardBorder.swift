import SwiftUI

enum ClimbCardBorderAnimationStyle {
    case full
    case ambient
    case `static`
}

struct AnimatedClimbCardBorder: ViewModifier {
    let colors: [Color]
    let shadowColor: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let isEmphasized: Bool
    let animationStyle: ClimbCardBorderAnimationStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseShadow = false
    @State private var rotationAngle: Double = 0

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
                if shouldRotate {
                    withAnimation(.linear(duration: rotationDuration).repeatForever(autoreverses: false)) {
                        rotationAngle = 360
                    }
                }

                if shouldPulseShadow {
                    withAnimation(.easeInOut(duration: shadowPulseDuration).repeatForever(autoreverses: true)) {
                        pulseShadow = true
                    }
                }
            }
    }

    private var shouldRotate: Bool {
        false
    }

    private var shouldPulseShadow: Bool {
        false
    }

    private var shouldShowMovingHighlight: Bool {
        false
    }

    private var shouldShowAmbientHighlight: Bool {
        false
    }

    private var rotationDuration: Double {
        if animationStyle == .ambient {
            return isEmphasized ? 11.4 : 8.8
        }

        return isEmphasized ? 13.2 : 10.8
    }

    private var shadowPulseDuration: Double {
        isEmphasized ? 3.4 : 4.0
    }

    private var secondaryRotationOffset: Double {
        isEmphasized ? -22 : -18
    }

    private var highlightLeadAngle: Double {
        isEmphasized ? 58 : 46
    }

    private var shadowOpacity: Double {
        if reduceMotion || animationStyle == .static {
            return isEmphasized ? 0.12 : 0.08
        }

        if animationStyle == .ambient {
            return isEmphasized ? 0.18 : 0.11
        }

        if isEmphasized {
            return pulseShadow ? 0.3 : 0.16
        }

        return pulseShadow ? 0.18 : 0.1
    }

    private var shadowRadius: CGFloat {
        if reduceMotion || animationStyle == .static {
            return isEmphasized ? 10 : 8
        }

        if animationStyle == .ambient {
            return isEmphasized ? 14 : 9
        }

        if isEmphasized {
            return pulseShadow ? 22 : 12
        }

        return pulseShadow ? 14 : 8
    }

    private var resolvedColors: [Color] {
        let baseColors = colors.isEmpty ? [.white.opacity(0.2)] : colors

        if baseColors.count == 1 {
            let color = baseColors[0]
            return [
                color.lighter(by: 0.1),
                color,
                color.darker(by: 0.12),
                color
            ]
        }

        let opacity = isEmphasized
            ? (shouldRotate ? 0.96 : 0.72)
            : (shouldRotate ? 0.88 : 0.62)

        return baseColors.map { $0.opacity(opacity) }
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    colors: resolvedColors,
                    center: .center,
                    angle: .degrees(rotationAngle)
                ),
                lineWidth: lineWidth
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: resolvedColors.map { $0.opacity(secondaryBorderOpacity) },
                            center: .center,
                            angle: .degrees(rotationAngle + secondaryRotationOffset)
                        ),
                        lineWidth: lineWidth + (isEmphasized ? 1.2 : 0.8)
                    )
                    .blur(radius: secondaryBlurRadius)
            }
            .overlay {
                if shouldShowMovingHighlight {
                    movingHighlightOverlay
                } else if shouldShowAmbientHighlight {
                    ambientHighlightOverlay
                }
            }
    }

    private var secondaryBorderOpacity: Double {
        if reduceMotion || animationStyle == .static {
            return 0.18
        }

        if animationStyle == .ambient {
            return isEmphasized ? 0.36 : 0.24
        }

        return isEmphasized ? 0.54 : 0.34
    }

    private var secondaryBlurRadius: CGFloat {
        if reduceMotion || animationStyle == .static {
            return 1.5
        }

        if animationStyle == .ambient {
            return isEmphasized ? 2.4 : 1.8
        }

        return isEmphasized ? 5.5 : 3.2
    }

    private var movingHighlightOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    stops: highlightStops,
                    center: .center,
                    angle: .degrees(rotationAngle + highlightLeadAngle)
                ),
                lineWidth: lineWidth + (isEmphasized ? 1.6 : 1.1)
            )
            .blur(radius: isEmphasized ? 1.2 : 0.8)
            .shadow(color: shadowColor.opacity(isEmphasized ? 0.7 : 0.46), radius: isEmphasized ? 8 : 5)
            .blendMode(.plusLighter)
    }

    private var ambientHighlightOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    stops: highlightStops,
                    center: .center,
                    angle: .degrees(rotationAngle + highlightLeadAngle)
                ),
                lineWidth: lineWidth + (isEmphasized ? 1.1 : 0.8)
            )
            .opacity(isEmphasized ? 0.78 : 0.64)
    }

    private var highlightStops: [Gradient.Stop] {
        let palette = highlightPalette

        guard palette.count > 1 else {
            let edgeGlow = palette[0]
            let coreGlow = Color.white.opacity(isEmphasized ? 0.98 : 0.86)

            return [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.68),
                .init(color: edgeGlow.opacity(0.0), location: 0.79),
                .init(color: edgeGlow.opacity(isEmphasized ? 0.52 : 0.4), location: 0.86),
                .init(color: coreGlow, location: 0.9),
                .init(color: edgeGlow.opacity(isEmphasized ? 0.74 : 0.58), location: 0.94),
                .init(color: .clear, location: 0.985),
                .init(color: .clear, location: 1.0)
            ]
        }

        let fadeStart = 0.7
        let arcStart = 0.79
        let arcEnd = 0.985
        let span = arcEnd - arcStart

        var stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0.0),
            .init(color: .clear, location: fadeStart),
            .init(color: palette[0].opacity(0.0), location: arcStart - 0.03)
        ]

        for (index, color) in palette.enumerated() {
            let progress = Double(index) / Double(max(palette.count - 1, 1))
            let location = arcStart + (span * progress)
            let opacity = isEmphasized ? 0.96 : 0.82
            stops.append(.init(color: color.opacity(opacity), location: location))
        }

        stops.append(.init(color: palette[palette.count - 1].opacity(0.0), location: arcEnd))
        stops.append(.init(color: .clear, location: 1.0))

        return stops
    }

    private var highlightPalette: [Color] {
        let basePalette = colors.isEmpty ? [shadowColor] : colors

        if basePalette.count == 1 {
            return [basePalette[0].lighter(by: isEmphasized ? 0.18 : 0.12)]
        }

        return basePalette.map { color in
            color.lighter(by: isEmphasized ? 0.12 : 0.08)
        }
    }
}

extension View {
    func animatedClimbCardBorder(
        colors: [Color],
        shadowColor: Color,
        cornerRadius: CGFloat = 28,
        lineWidth: CGFloat = 1.5,
        isEmphasized: Bool = false,
        animationStyle: ClimbCardBorderAnimationStyle = .static
    ) -> some View {
        modifier(
            AnimatedClimbCardBorder(
                colors: colors,
                shadowColor: shadowColor,
                cornerRadius: cornerRadius,
                lineWidth: lineWidth,
                isEmphasized: isEmphasized,
                animationStyle: animationStyle
            )
        )
    }
}
