import SwiftUI

struct RoutineDetailView: View {
    let routine: Routine
    var onStart: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var showDeleteConfirmation = false
    @State private var isSavedToMyRoutines = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    intervalsSection
                    actionsSection
                }
                .padding(20)
            }
            .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(Color.customGray)
                }

                ToolbarItem(placement: .principal) {
                    Text(routine.name)
                        .font(.montserratSemiBold(size: 17))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if routine.isBuiltIn {
                        Button(action: toggleSavedState) {
                            Image(systemName: isSavedToMyRoutines ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(isSavedToMyRoutines ? .accent : .white.opacity(0.3))
                        }
                    } else {
                        Button(action: { onEdit?() }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .onAppear {
                refreshSavedState()
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
            detailStatsRow
            completionStatsView
            RoutineIntensityChartCard(routine: routine)

            if !routine.routineDescription.isEmpty {
                Text(routine.routineDescription)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(Color.customGray)
            }
        }
    }

    private var completionStatsView: some View {
        RoutineCompletionStatusCard(
            completionCount: routine.completionCount,
            lastCompletedAt: routine.lastCompletedAt
        )
    }

    private var detailStatsRow: some View {
        HStack(spacing: 0) {
            detailStatItem(value: durationValue, label: "min")
            detailStatDivider
            detailStatItem(value: "\(routine.intervalCount)", label: "intervals")
            detailStatDivider
            detailStatItem(
                value: difficultyLabel,
                label: "difficulty",
                valueColor: difficultyColor,
                valueFontSize: 14
            )
        }
    }

    private var detailStatDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1, height: 40)
    }

    private func detailStatItem(
        value: String,
        label: String,
        valueColor: Color = .white,
        valueFontSize: CGFloat = 22
    ) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.montserratBold(size: valueFontSize))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.montserratRegular(size: 12))
                .foregroundStyle(Color.customGray)
        }
        .frame(maxWidth: .infinity)
    }

    private var difficultyLabel: String {
        guard let difficulty = routine.difficulty else { return "-" }
        return RoutineDifficultyStyle.label(for: difficulty)
    }

    private var difficultyColor: Color {
        guard let difficulty = routine.difficulty else { return .white }
        return RoutineDifficultyStyle.color(for: difficulty, colorScheme: colorScheme)
    }

    private var durationValue: String {
        let totalMinutes = Int((routine.totalDuration / 60).rounded())
        return "\(totalMinutes)"
    }

    private var intervalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Intervals")
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                ForEach(routine.intervals, id: \.id) { interval in
                    RoutineIntervalDetailRow(
                        interval: interval,
                        totalDuration: routine.totalDuration
                    )
                }
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
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
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.accent)
                )
            }
            .buttonStyle(.plain)

            if !routine.isBuiltIn {
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                        Text("Delete Routine")
                            .font(.montserratMedium(size: 14))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.red.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func refreshSavedState() {
        guard routine.isBuiltIn,
              let templateId = routine.templateId else {
            isSavedToMyRoutines = false
            return
        }

        let service = RoutineService(modelContext: modelContext)
        isSavedToMyRoutines = (try? service.savedCopy(templateId: templateId)) != nil
    }

    private func toggleSavedState() {
        guard routine.isBuiltIn else { return }

        let service = RoutineService(modelContext: modelContext)

        do {
            isSavedToMyRoutines = try service.toggleSavedCopy(for: routine)
        } catch {
            print("Failed to toggle saved state for routine: \(error)")
        }
    }
}

#Preview {
    RoutineDetailView(
        routine: BuiltInRoutines.previewTemplates[0],
        onStart: {},
        onEdit: {},
        onCopy: {}
    )
}

#Preview("Dark Mode") {
    RoutineDetailView(
        routine: BuiltInRoutines.previewTemplates[5],
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
