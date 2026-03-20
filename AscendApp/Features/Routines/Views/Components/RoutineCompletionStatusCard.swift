import SwiftUI

struct RoutineCompletionStatusCard: View {
    let completionCount: Int
    let lastCompletedAt: Date?

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        RoutineCardSurface(
            cornerRadius: 12,
            darkFillOpacity: 0.35,
            lightFillOpacity: 0.08,
            darkStrokeOpacity: 0,
            lightStrokeOpacity: 0
        ) {
            HStack(spacing: 8) {
                Image(systemName: completionCount > 0 ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(completionCount > 0 ? .green : .gray)

                if completionCount == 0 {
                    Text("Not yet completed")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                } else {
                    Text("Completed \(completionCount) \(completionCount == 1 ? "time" : "times")")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))

                    if let lastCompletedAt {
                        Text("•")
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray)
                        Text(lastCompletedAt.relativeFormatted)
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    }
                }

                Spacer()
            }
            .padding(12)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        RoutineCompletionStatusCard(completionCount: 0, lastCompletedAt: nil)
        RoutineCompletionStatusCard(completionCount: 3, lastCompletedAt: .now.addingTimeInterval(-86_400))
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
