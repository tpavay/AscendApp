import SwiftUI

struct EmptyRoutinesView: View {
    var onCreateRoutine: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            AppIcon(token: .tabWorkouts, pointSize: 48)
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.4))

            Text("No routines yet")
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

            Text("Create your first routine to get started with guided workouts")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let onCreateRoutine {
                Button(action: onCreateRoutine) {
                    HStack {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Create Routine")
                            .font(.montserratSemiBold(size: 14))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.accent)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    EmptyRoutinesView(onCreateRoutine: {})
        .padding(20)
}

#Preview("Dark Mode") {
    EmptyRoutinesView(onCreateRoutine: {})
        .padding(20)
        .preferredColorScheme(.dark)
}
