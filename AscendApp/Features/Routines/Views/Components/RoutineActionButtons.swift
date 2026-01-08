import SwiftUI

struct RoutineActionButtons: View {
    var onCreateRoutine: () -> Void
    var onExploreRoutines: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Create Routine Button
            Button(action: onCreateRoutine) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16, weight: .medium))
                    Text("Create routine")
                        .font(.montserratMedium(size: 14))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.accent)
                )
            }
            .buttonStyle(.plain)

            // Explore Routines Button
            Button(action: onExploreRoutines) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                    Text("Explore routines")
                        .font(.montserratMedium(size: 14))
                }
                .foregroundStyle(.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.accent, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    RoutineActionButtons(
        onCreateRoutine: {},
        onExploreRoutines: {}
    )
    .padding(20)
}

#Preview("Dark Mode") {
    RoutineActionButtons(
        onCreateRoutine: {},
        onExploreRoutines: {}
    )
    .padding(20)
    .preferredColorScheme(.dark)
}
