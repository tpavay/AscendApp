@preconcurrency import FirebaseAuth
import SwiftData
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
    @Environment(ModerationStore.self) private var moderationStore
    @State private var themeManager = ThemeManager.shared
    @State private var showDeleteConfirmation = false
    @State private var isSavedToMyRoutines = false
    @State private var leaderboardViewModel: RoutineLeaderboardViewModel
    @State private var selectedPage = 0
    @State private var detailPageHeights: [Int: CGFloat] = [:]
    @State private var historySummary = RoutineHistorySummary.empty

    init(
        routine: Routine,
        onStart: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onCopy: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.routine = routine
        self.onStart = onStart
        self.onEdit = onEdit
        self.onCopy = onCopy
        self.onDelete = onDelete
        _leaderboardViewModel = State(initialValue: RoutineLeaderboardViewModel(routine: routine))
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private static let detailPageTitles = [
        "OVERVIEW",
        "HISTORY",
        "LEADERBOARD"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    routineIntroSection
                    actionsSection
                    detailPageSelector
                    detailPages
                }
                .padding(20)
            }
            .background(Color.black)
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

                ToolbarItem(placement: .topBarTrailing) {
                    if routine.completionCount > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.ascendAccent)
                            .accessibilityLabel("Completed \(routine.completionCount) time\(routine.completionCount == 1 ? "" : "s")")
                    }
                }
            }
            .onAppear {
                refreshSavedState()
                refreshHistorySummary()
            }
            .task(id: routine.id) {
                leaderboardViewModel.updateRoutine(routine)
                refreshHistorySummary()
                await leaderboardViewModel.refresh()
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

    // MARK: - Detail Pages

    private var detailPageSelector: some View {
        HStack(spacing: 4) {
            ForEach(Self.detailPageTitles.indices, id: \.self) { index in
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        selectedPage = index
                    }
                } label: {
                    Text(Self.detailPageTitles[index])
                        .font(.montserratBold(size: 11))
                        .tracking(1.1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(index == selectedPage ? Color.ascendAccent : selectorInactiveTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if index == selectedPage {
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.07))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(Color.ascendAccent.opacity(0.45), lineWidth: 1)
                                    )
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.detailPageTitles[index].capitalized)
                .accessibilityValue(index == selectedPage ? "Selected" : "")
            }
        }
        .padding(4)
        .background(selectorBackgroundColor, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(selectorStrokeColor, lineWidth: 1)
        }
        .animation(.smooth(duration: 0.25), value: selectedPage)
    }

    private var detailPages: some View {
        ZStack(alignment: .topLeading) {
            selectedDetailPageMeasurer

            TabView(selection: $selectedPage) {
                ForEach(0..<Self.detailPageTitles.count, id: \.self) { pageIndex in
                    detailPageContent(for: pageIndex)
                        .tag(pageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: detailPageHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .onPreferenceChange(RoutineDetailPageHeightPreferenceKey.self) { heights in
            detailPageHeights.merge(heights) { _, newValue in newValue }
        }
        .animation(.smooth(duration: 0.25), value: detailPageHeight)
    }

    private var selectedDetailPageMeasurer: some View {
        detailPageContent(for: selectedPage)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: RoutineDetailPageHeightPreferenceKey.self,
                        value: [selectedPage: geometry.size.height]
                    )
                }
            )
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var detailPageHeight: CGFloat {
        detailPageHeights[selectedPage] ?? detailPageHeights.values.max() ?? 360
    }

    @ViewBuilder
    private func detailPageContent(for pageIndex: Int) -> some View {
        switch pageIndex {
        case 0:
            overviewPage
        case 1:
            historyPage
        case 2:
            leaderboardPage
        default:
            EmptyView()
        }
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            intervalsSection
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            if historySummary.entries.isEmpty {
                Text("Completed routine sessions will show up here.")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
            } else {
                historyMetricsGrid
                    .padding(.vertical, 2)

                Text("RECENT SESSIONS")
                    .font(.montserratSemiBold(size: 12))
                    .tracking(1.2)
                    .foregroundStyle(Color.customGray)

                VStack(spacing: 0) {
                    ForEach(historySummary.recentEntries) { entry in
                        historyRow(for: entry)
                    }
                }
                .padding(.top, -2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var leaderboardPage: some View {
        ReplayCompletionLeaderboardView(
            rows: moderationStore.moderate(leaderboardViewModel.rows),
            completedCount: leaderboardViewModel.completedCount,
            isLoading: leaderboardViewModel.isLoading,
            isLoadingMore: leaderboardViewModel.isLoadingMore,
            fetchFailed: leaderboardViewModel.fetchFailed,
            currentUserPhotoURL: currentUserPhotoURL,
            effectiveColorScheme: effectiveColorScheme,
            emptyTitle: "No completed runs yet.",
            emptyMessage: "Be the first to put steps on this routine.",
            emphasis: leaderboardViewModel.rowEmphasis,
            onRowAppear: { row in
                leaderboardViewModel.loadMoreIfNeeded(currentRowID: row.id)
            }
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectorInactiveTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.64) : .black.opacity(0.56)
    }

    private var selectorBackgroundColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.045)
    }

    private var selectorStrokeColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08)
    }

    // MARK: - Intro Section

    private var routineIntroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoutineHeroVisualization(
                intervals: routine.intervals,
                totalDuration: routine.totalDuration
            )

            if !routine.routineDescription.isEmpty {
                Text(routine.routineDescription)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(Color.customGray)
            }

            inlineStatsRow
        }
    }

    // MARK: - Inline stats row (replaces the wide divided columns)

    private var inlineStatsRow: some View {
        HStack(spacing: 8) {
            statPill(text: "\(durationValue) min")
            statPill(text: "\(routine.intervalCount) intervals")
            statPill(text: difficultyLabel, valueColor: difficultyColor)
            Spacer(minLength: 0)
        }
    }

    private func statPill(text: String, valueColor: Color = .white.opacity(0.92)) -> some View {
        Text(text)
            .font(.montserratSemiBold(size: 12))
            .foregroundStyle(valueColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
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

    // MARK: - History Section

    private var historyMetrics: [RoutineHistoryMetric] {
        var metrics = [
            RoutineHistoryMetric(
                id: "sessions",
                value: historySummary.sessionsCount.formatted(),
                label: "SESSIONS"
            ),
            RoutineHistoryMetric(
                id: "completions",
                value: historySummary.completionsCount.formatted(),
                label: "COMPLETIONS"
            )
        ]

        if let bestSteps = historySummary.bestSteps {
            metrics.append(RoutineHistoryMetric(
                id: "best_steps",
                value: bestSteps.formatted(),
                label: "BEST STEPS"
            ))
        }

        if let bestAverageSPM = historySummary.bestAverageSPM {
            metrics.append(RoutineHistoryMetric(
                id: "best_spm",
                value: Int(bestAverageSPM.rounded()).formatted(),
                label: "BEST SPM"
            ))
        }

        return metrics
    }

    private var historyMetricColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 72), spacing: 14),
            count: min(historyMetrics.count, 4)
        )
    }

    private var historyMetricsGrid: some View {
        LazyVGrid(columns: historyMetricColumns, alignment: .leading, spacing: 14) {
            ForEach(historyMetrics) { metric in
                historyMetric(value: metric.value, label: metric.label)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedPage)
    }

    private func historyMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.montserratBold(size: 24))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.montserratSemiBold(size: 10))
                .tracking(1.0)
                .foregroundStyle(Color.customGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historyRow(for entry: RoutineHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text(historyRowSubtitle(for: entry))
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.5))
            }

            Spacer(minLength: 0)

            if entry.isCompleted {
                historyBadge(
                    title: "DONE",
                    foreground: .black,
                    background: .accent
                )
            }

            Text(DurationFormatter.format(duration: entry.duration))
                .font(.montserratBold(size: 17))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .monospacedDigit()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func historyBadge(title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.montserratSemiBold(size: 11))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
    }

    private func historyRowSubtitle(for entry: RoutineHistoryEntry) -> String {
        let spmText = Int(entry.stepsPerMinute.rounded()).formatted()
        return "\(entry.steps.formatted()) steps · \(spmText) SPM"
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
            debugLog("Failed to toggle saved state for routine: \(error)")
        }
    }

    private func refreshHistorySummary() {
        let contextType: WorkoutParticipationContextType
        let contextId: String

        if routine.source.isTemplate,
           let templateId = routine.templateId,
           !templateId.isEmpty {
            contextType = .routineTemplate
            contextId = templateId
        } else {
            contextType = .routine
            contextId = routine.id.uuidString
        }

        let contextTypeRawValue = contextType.rawValue
        let descriptor = FetchDescriptor<WorkoutParticipation>(
            predicate: #Predicate {
                $0.contextTypeRawValue == contextTypeRawValue &&
                    $0.contextId == contextId
            }
        )

        do {
            let entries = try modelContext.fetch(descriptor)
                .compactMap { participation -> RoutineHistoryEntry? in
                    guard let workout = participation.workout else { return nil }
                    let snapshot = participation.metricsSnapshot ?? WorkoutParticipationMetricsSnapshot(workout: workout)
                    return RoutineHistoryEntry(
                        id: participation.id,
                        date: snapshot.startedAt,
                        duration: snapshot.durationSeconds,
                        steps: snapshot.steps,
                        stepsPerMinute: snapshot.stepsPerMinute,
                        isCompleted: isCompletedRoutineDuration(snapshot.durationSeconds)
                    )
                }
                .sorted { $0.date > $1.date }

            historySummary = RoutineHistorySummary(entries: entries)
        } catch {
            historySummary = .empty
        }
    }

    private func isCompletedRoutineDuration(_ duration: TimeInterval) -> Bool {
        guard routine.totalDuration > 0 else { return true }
        return duration >= max(routine.totalDuration * 0.95, routine.totalDuration - 5)
    }

    private var currentUserPhotoURL: URL? {
        if let cachedURL = UserDataRepository.shared.getCachedProfilePictureURL()
            .flatMap(URL.init(string:)) {
            return cachedURL
        }

        return Auth.auth().currentUser?.photoURL
    }
}

private struct RoutineHistoryMetric: Identifiable {
    let id: String
    let value: String
    let label: String
}

private struct RoutineHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let steps: Int
    let stepsPerMinute: Double
    let isCompleted: Bool
}

private struct RoutineHistorySummary: Equatable {
    let entries: [RoutineHistoryEntry]

    var recentEntries: [RoutineHistoryEntry] {
        Array(entries.prefix(8))
    }

    var sessionsCount: Int {
        entries.count
    }

    var completionsCount: Int {
        entries.filter(\.isCompleted).count
    }

    var bestSteps: Int? {
        entries.map(\.steps).max()
    }

    var bestAverageSPM: Double? {
        entries.map(\.stepsPerMinute).max()
    }

    static let empty = RoutineHistorySummary(entries: [])
}

private struct RoutineDetailPageHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, newValue in newValue }
    }
}

#Preview {
    RoutineDetailView(
        routine: BuiltInRoutines.previewTemplates[0],
        onStart: {},
        onEdit: {},
        onCopy: {}
    )
    .environment(ModerationStore.shared)
}

#Preview("Dark Mode") {
    RoutineDetailView(
        routine: BuiltInRoutines.previewTemplates[5],
        onStart: {},
        onEdit: {},
        onCopy: {}
    )
    .environment(ModerationStore.shared)
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
