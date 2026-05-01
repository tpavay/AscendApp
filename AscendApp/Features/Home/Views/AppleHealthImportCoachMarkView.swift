import SwiftUI

struct AppleHealthImportCoachMarkView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var themeManager = ThemeManager.shared
    @State private var isPointerAnimating = false

    let pointerX: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private let cardWidth: CGFloat = 248
    private let pointerSize: CGFloat = 22

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    private var backgroundColor: Color {
        effectiveColorScheme == .dark ? .jetLighter.opacity(0.98) : .white
    }

    private var borderColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.72) : .gray
    }

    private var clampedPointerX: CGFloat {
        min(max(pointerX, 22), cardWidth - 22)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import workouts here")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(primaryTextColor)

                    Text("Bring in Apple Health or other connected workouts, and review new auto-imports in one place.")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss import tip")
            }

            HStack(spacing: 10) {
                Button("Not now", action: onDismiss)
                    .appSheetButtonStyle(tone: .secondary)

                Button("Open", action: onOpen)
                    .appSheetButtonStyle()
            }
        }
        .padding(14)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.accent)
                .shadow(color: .accent.opacity(0.24), radius: 10, y: 4)
                .offset(
                    x: clampedPointerX - (pointerSize / 2),
                    y: reduceMotion ? -10 : (isPointerAnimating ? -16 : -10)
                )
        }
        .shadow(color: .black.opacity(effectiveColorScheme == .dark ? 0.28 : 0.12), radius: 18, y: 10)
        .onAppear {
            guard !reduceMotion else { return }

            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPointerAnimating = true
            }
        }
    }
}

#Preview {
    AppleHealthImportCoachMarkView(
        pointerX: 214,
        onOpen: {},
        onDismiss: {}
    )
    .padding()
    .themedBackground()
}
