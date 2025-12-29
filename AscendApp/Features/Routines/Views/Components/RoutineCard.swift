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

                // Description (if exists)
                if !routine.routineDescription.isEmpty {
                    Text(routine.routineDescription)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .lineLimit(2)
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

                // Interval preview
                if !routine.intervals.isEmpty {
                    intervalPreview
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var intervalPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(routine.intervals.prefix(5)) { interval in
                    VStack(spacing: 2) {
                        Text(interval.intensityDisplayShort)
                            .font(.montserratSemiBold(size: 12))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        Text(interval.durationFormattedShort)
                            .font(.montserratRegular(size: 10))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                    )
                }

                if routine.intervals.count > 5 {
                    Text("+\(routine.intervals.count - 5)")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Difficulty Indicator

struct DifficultyIndicator: View {
    let level: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var label: String {
        switch level {
        case 1: return "Easy"
        case 2: return "Light"
        case 3: return "Moderate"
        case 4: return "Hard"
        case 5: return "Intense"
        default: return "Unknown"
        }
    }

    private var color: Color {
        switch level {
        case 1: return .green
        case 2: return .teal
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .gray
        }
    }

    var body: some View {
        Text(label)
            .font(.montserratMedium(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
}

#Preview("Routine Card") {
    VStack(spacing: 16) {
        RoutineCard(routine: BuiltInRoutines.beginner20Min)
        RoutineCard(routine: BuiltInRoutines.hiitIntervals)
    }
    .padding(20)
}

#Preview("Dark Mode") {
    VStack(spacing: 16) {
        RoutineCard(routine: BuiltInRoutines.beginner20Min)
        RoutineCard(routine: BuiltInRoutines.hiitIntervals)
    }
    .padding(20)
    .preferredColorScheme(.dark)
}
