import SwiftUI

struct RoutineCardSurface<Content: View>: View {
    var cornerRadius: CGFloat = 14
    var darkFillOpacity: CGFloat = 0.2
    var lightFillOpacity: CGFloat = 0.06
    var darkStrokeOpacity: CGFloat = 0.1
    var lightStrokeOpacity: CGFloat = 0.15
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
    }

    private var backgroundColor: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(darkFillOpacity) : .gray.opacity(lightFillOpacity)
    }

    private var borderColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(darkStrokeOpacity) : .gray.opacity(lightStrokeOpacity)
    }
}

#Preview {
    RoutineCardSurface {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routine Surface")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(.white)

            Text("Reusable container for routine cards.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
