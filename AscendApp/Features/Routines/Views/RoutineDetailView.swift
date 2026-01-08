import SwiftUI

struct RoutineDetailView: View {
    let routine: Routine
    var onStart: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var showDeleteConfirmation = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header info
                    headerSection

                    // Intervals list
                    intervalsSection

                    // Actions
                    actionsSection
                }
                .padding(20)
            }
            .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(.accent)
                }

                if !routine.isBuiltIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(action: { onEdit?() }) {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.accent)
                        }
                    }
                }
            }
            .alert("Delete Routine?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Stats row
            HStack(spacing: 24) {
                statItem(icon: "clock", value: routine.totalDurationFormatted, label: "Duration")
                statItem(icon: "list.bullet", value: "\(routine.intervalCount)", label: "Intervals")

                if let difficulty = routine.difficulty {
                    VStack(spacing: 4) {
                        DifficultyIndicator(level: difficulty)
                        Text("Difficulty")
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    }
                }

                Spacer()
            }

            // Completion stats
            completionStatsView

            // Description
            if !routine.routineDescription.isEmpty {
                Text(routine.routineDescription)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            }

            // Source badge
            if routine.isBuiltIn {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                    Text("Built-in Template")
                        .font(.montserratMedium(size: 12))
                }
                .foregroundStyle(.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.accent.opacity(0.15))
                )
            }
        }
    }

    private var completionStatsView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(routine.completionCount > 0 ? .green : .gray)

            if routine.completionCount == 0 {
                Text("Not yet completed")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
            } else {
                Text("Completed \(routine.completionCount) \(routine.completionCount == 1 ? "time" : "times")")
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))

                if let lastCompleted = routine.lastCompletedAt {
                    Text("•")
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray)
                    Text(lastCompleted.relativeFormatted)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.08))
        )
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(value)
                    .font(.montserratSemiBold(size: 16))
            }
            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text(label)
                .font(.montserratRegular(size: 12))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
        }
    }

    // MARK: - Intervals Section

    private var intervalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Intervals")
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            VStack(spacing: 8) {
                ForEach(Array(routine.intervals.enumerated()), id: \.element.id) { index, interval in
                    IntervalDetailRow(interval: interval, index: index + 1)
                }
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Start button
            Button(action: {
                dismiss()
                onStart?()
            }) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Start Routine")
                        .font(.montserratSemiBold(size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.accent)
                )
            }
            .buttonStyle(.plain)

            // Copy button (for built-in templates)
            if routine.isBuiltIn {
                Button(action: {
                    onCopy?()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                        Text("Copy to My Routines")
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
        .padding(.top, 8)
    }
}

// MARK: - Interval Detail Row

struct IntervalDetailRow: View {
    let interval: RoutineInterval
    let index: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Index number
            Text("\(index)")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.accent)
                )

            // Intensity
            VStack(alignment: .leading, spacing: 2) {
                Text(interval.intensityDisplay)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                // Modifiers
                if interval.modifiers.hasAnyActive {
                    Text(interval.modifiers.activeModifiers.joined(separator: " • "))
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.accent)
                }
            }

            Spacer()

            // Duration
            Text(interval.durationFormatted)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.05))
        )
    }
}

#Preview {
    RoutineDetailView(
        routine: BuiltInRoutines.beginner20Min,
        onStart: {},
        onEdit: {},
        onCopy: {}
    )
}

#Preview("Dark Mode") {
    RoutineDetailView(
        routine: BuiltInRoutines.hiitIntervals,
        onStart: {},
        onEdit: {},
        onCopy: {}
    )
    .preferredColorScheme(.dark)
}

// MARK: - Date Extension

extension Date {
    /// Returns a relative formatted string like "2 days ago", "Just now", etc.
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
