import SwiftUI

struct RoutineCard: View {
    let routine: Routine
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        Button(action: { onTap?() }) {
            RoutineCardSurface(cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    // Header: Name and badge
                    HStack {
                        Text(routine.name)
                            .font(.montserratSemiBold(size: 18))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .lineLimit(1)

                        Spacer()

                        if routine.isBuiltIn {
                            Text("BUILT-IN")
                                .font(.montserratMedium(size: 10))
                                .foregroundStyle(.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.accent.opacity(0.15))
                                )
                        }
                    }

                    // Stats row
                    HStack(spacing: 16) {
                        // Duration
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 12, weight: .medium))
                            Text(routine.totalDurationFormatted)
                                .font(.montserratMedium(size: 14))
                        }
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                        // Interval count
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 12, weight: .medium))
                            Text("\(routine.intervalCount) intervals")
                                .font(.montserratMedium(size: 14))
                        }
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                        Spacer()

                        // Difficulty (for built-in templates)
                        if let difficulty = routine.difficulty {
                            DifficultyIndicator(level: difficulty)
                        }
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Routine Card") {
    VStack(spacing: 16) {
        RoutineCard(routine: BuiltInRoutines.previewTemplates[0])
        RoutineCard(routine: BuiltInRoutines.previewTemplates[5])
    }
    .padding(20)
}

#Preview("Dark Mode") {
    VStack(spacing: 16) {
        RoutineCard(routine: BuiltInRoutines.previewTemplates[0])
        RoutineCard(routine: BuiltInRoutines.previewTemplates[5])
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
