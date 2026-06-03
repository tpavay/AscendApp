import SwiftUI

struct ClimbSplitCardSurface<Leading: View, Content: View>: View {
    let leadingWidth: CGFloat
    let minimumHeight: CGFloat
    let glowColor: Color
    let borderColors: [Color]
    let shadowColor: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let isEmphasizedBorderStyle: Bool
    let borderAnimationStyle: ClimbCardBorderAnimationStyle
    let leading: Leading
    let content: Content

    init(
        leadingWidth: CGFloat = 112,
        minimumHeight: CGFloat = 140,
        glowColor: Color,
        borderColors: [Color],
        shadowColor: Color,
        cornerRadius: CGFloat = 28,
        lineWidth: CGFloat = 1.25,
        isEmphasizedBorderStyle: Bool = false,
        borderAnimationStyle: ClimbCardBorderAnimationStyle = .static,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) {
        self.leadingWidth = leadingWidth
        self.minimumHeight = minimumHeight
        self.glowColor = glowColor
        self.borderColors = borderColors
        self.shadowColor = shadowColor
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.isEmphasizedBorderStyle = isEmphasizedBorderStyle
        self.borderAnimationStyle = borderAnimationStyle
        self.leading = leading()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: leadingWidth)
                .frame(maxHeight: .infinity)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .background(cardBackground)
        .clipShape(cardShape)
        .animatedClimbCardBorder(
            colors: borderColors,
            shadowColor: shadowColor,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            isEmphasized: isEmphasizedBorderStyle,
            animationStyle: borderAnimationStyle
        )
    }

    private var cardBackground: some View {
        cardShape
            .fill(Color.black.opacity(0.96))
            .background(
                cardShape
                    .fill(glowColor)
                    .blur(radius: 24)
            )
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}
