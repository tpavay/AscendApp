import SwiftUI

struct HomeWorkoutActionSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    let onManualEntry: () -> Void
    let onStartRoutine: () -> Void
    let onImportWorkouts: () -> Void
    let pendingImportCount: Int

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        AppSheetScaffold(
            title: "Log Workout",
            message: "Choose the workout flow you want to start.",
            headerAlignment: .leading,
            contentAlignment: .leading,
            layout: .menu
        ) {
            VStack(spacing: 10) {
                optionButton(action: onManualEntry) {
                    AppSheetOptionRow(
                        systemImage: "pencil.line",
                        title: "Manual Entry",
                        subtitle: "Record a workout from scratch",
                        iconTint: effectiveColorScheme == .dark ? .white : .black,
                        trailingSymbol: "chevron.right"
                    )
                }

                optionButton(action: onStartRoutine) {
                    AppSheetOptionRow(
                        systemImage: "flag.checkered.2.crossed",
                        title: "Start Routine",
                        subtitle: "Open your guided interval workouts",
                        iconTint: .accent,
                        tone: .accent,
                        trailingSymbol: "chevron.right",
                        trailingTint: .accent
                    )
                }

                optionButton(action: onImportWorkouts) {
                    AppSheetOptionRow(
                        systemImage: "square.and.arrow.down",
                        title: "Import Workouts",
                        subtitle: "Apple Health and connected sources",
                        iconTint: .accent,
                        badgeCount: pendingImportCount,
                        trailingSymbol: "chevron.right",
                        trailingTint: .accent
                    )
                }
            }
        }
    }

    private func optionButton<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
        }
        .buttonStyle(.plain)
    }
}
