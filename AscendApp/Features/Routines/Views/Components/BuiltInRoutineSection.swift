import SwiftUI

struct BuiltInRoutineSection: View {
    let routines: [Routine]
    var onRoutineSelected: ((Routine) -> Void)? = nil
    var onCopyRoutine: ((Routine) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Built-in Templates")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                Text("\(routines.count) templates")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
            }

            // Horizontal scroll of template cards
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(routines) { routine in
                        BuiltInTemplateCard(
                            routine: routine,
                            onTap: { onRoutineSelected?(routine) },
                            onCopy: { onCopyRoutine?(routine) }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Built-in Template Card

struct BuiltInTemplateCard: View {
    let routine: Routine
    var onTap: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(routine.name)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .lineLimit(1)

                Spacer()

                if let difficulty = routine.difficulty {
                    DifficultyIndicator(level: difficulty)
                }
            }

            Spacer()

            // Stats
            HStack(spacing: 12) {
                Label(routine.totalDurationFormatted, systemImage: "clock")
                    .font(.montserratMedium(size: 12))

                Label("\(routine.intervalCount)", systemImage: "list.bullet")
                    .font(.montserratMedium(size: 12))
            }
            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

            // Action buttons
            HStack(spacing: 8) {
                Button(action: { onTap?() }) {
                    Text("View")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.accent, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: { onCopy?() }) {
                    Text("Copy")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 220, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    BuiltInRoutineSection(
        routines: BuiltInRoutines.templates,
        onRoutineSelected: { _ in },
        onCopyRoutine: { _ in }
    )
    .padding(20)
}

#Preview("Dark Mode") {
    BuiltInRoutineSection(
        routines: BuiltInRoutines.templates,
        onRoutineSelected: { _ in },
        onCopyRoutine: { _ in }
    )
    .padding(20)
    .preferredColorScheme(.dark)
}
