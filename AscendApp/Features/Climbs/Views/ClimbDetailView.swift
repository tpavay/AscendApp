import SwiftData
import SwiftUI

struct ClimbDetailView: View {
    let showsBrowseBackButton: Bool
    private let initialCollectionOrder: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var viewModel: ClimbDetailViewModel
    @State private var selectedPage = 0
    @State private var showingReplaceConfirmation = false
    @State private var showingEndClimbConfirmation = false
    @State private var showingBrowseClimbs = false
    @State private var showingWorkoutEntrySheet = false
    @State private var showingWorkoutForm = false
    @State private var showingImportSheet = false
    @State private var showingRoutinesView = false
    @State private var browseViewModel = GlobeViewModel()
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var actionErrorMessage: String?

    init(climb: Climb, showsBrowseBackButton: Bool = false, initialCollectionOrder: Int? = nil) {
        self.showsBrowseBackButton = showsBrowseBackButton
        self.initialCollectionOrder = initialCollectionOrder
        _viewModel = State(initialValue: ClimbDetailViewModel(climb: climb))
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard
                pageDots
                detailPages
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsBrowseBackButton)
        .toolbar {
            if showsBrowseBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back to Globe")
                                .font(.montserratMedium(size: 16))
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showingRoutinesView) {
            RoutinesView()
        }
        .navigationDestination(isPresented: $showingBrowseClimbs) {
            ClimbBrowseView(viewModel: browseViewModel)
        }
        .sheet(isPresented: $showingWorkoutEntrySheet) {
            HomeWorkoutActionSheet(
                onManualEntry: presentWorkoutForm,
                onStartRoutine: presentRoutines,
                onImportWorkouts: presentImportSheet,
                pendingImportCount: importCoordinator.pendingCount
            )
            .appSheetStyle(.fitted())
        }
        .sheet(isPresented: $showingWorkoutForm) {
            WorkoutFormView(
                showingWorkoutForm: $showingWorkoutForm,
                onWorkoutCompleted: { _ in
                    showingWorkoutForm = false
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingImportSheet) {
            WorkoutImportSheet()
        }
        .confirmationDialog(
            "Replace Active Climb?",
            isPresented: $showingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Current Climb", role: .destructive) {
                do {
                    try viewModel.replaceActiveClimb(modelContext: modelContext)
                } catch {
                    actionErrorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let conflictingActiveSummary = viewModel.conflictingActiveSummary {
                Text("Starting \(viewModel.climb.name) will abandon your current progress on \(conflictingActiveSummary.climb.name).")
            }
        }
        .confirmationDialog(
            "End Active Climb?",
            isPresented: $showingEndClimbConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Climb", role: .destructive) {
                do {
                    try viewModel.abandonActiveClimb(modelContext: modelContext)
                } catch {
                    actionErrorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop tracking progress for \(viewModel.climb.name). You can start it again later, but this attempt will be abandoned.")
        }
        .alert("Climb Action Error", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "Something went wrong.")
        }
        .task {
            importCoordinator.configure(modelContext: modelContext)
            viewModel.refresh(modelContext: modelContext)
            if let initialCollectionOrder {
                viewModel.collectionOrder = initialCollectionOrder
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
        }
    }

    private var heroCard: some View {
        let heroShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return ZStack(alignment: .bottomLeading) {
            ClimbArtworkView(climb: viewModel.climb, variant: .hero)

            LinearGradient(
                colors: [
                    .black.opacity(0.03),
                    .black.opacity(0.1),
                    .black.opacity(0.22),
                    .black.opacity(0.52)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let stripOrderText = viewModel.stripOrderText {
                HStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 28,
                            bottomLeading: 28,
                            bottomTrailing: 0,
                            topTrailing: 0
                        ),
                        style: .continuous
                    )
                        .fill(viewModel.climb.tier.detailStripStyle)
                        .frame(width: 48)
                        .overlay {
                            Text(stripOrderText)
                                .font(.montserratBold(size: 13))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(-90))
                                .lineLimit(1)
                        }

                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.18),
                        .black.opacity(0.68),
                        .black.opacity(0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 132)
            }

            heroTextOverlay
        }
        .frame(maxWidth: .infinity)
        .frame(height: 390)
        .clipShape(heroShape)
        .animatedClimbCardBorder(
            colors: viewModel.climb.tier.borderColors,
            shadowColor: viewModel.climb.tier.shadowColor,
            cornerRadius: 28,
            lineWidth: 1.8,
            isEmphasized: viewModel.climb.tier.usesEmphasizedBorderStyle
        )
    }

    private var heroTextOverlay: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(viewModel.climb.name)
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(viewModel.subtitle)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .shadow(color: .black.opacity(0.55), radius: 16, x: 0, y: 4)
        .padding(.leading, viewModel.stripOrderText == nil ? 20 : 64)
        .padding(.trailing, 16)
        .padding(.bottom, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var pageDots: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            ForEach(0..<3, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == selectedPage ? viewModel.climb.tier.color : .white.opacity(0.18))
                    .frame(width: index == selectedPage ? 24 : 8, height: 8)
            }

            Spacer(minLength: 0)
        }
    }

    private var detailPages: some View {
        TabView(selection: $selectedPage) {
            overviewPage.tag(0)
            historyPage.tag(1)
            leaderboardPage.tag(2)
        }
        .frame(height: 500)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.18), value: selectedPage)
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                metricCell(value: viewModel.climb.referenceStepCount.formatted(), title: "STEPS")
                metricDivider
                metricCell(value: viewModel.climb.calculatedFloors.formatted(), title: "FLOORS")
                metricDivider
                metricCell(value: viewModel.estimatedTimeText, title: "EST. TIME")
            }
            .frame(height: 58, alignment: .top)

            if let progressSummary = viewModel.progressSummary {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Current Progress")
                            .font(.montserratSemiBold(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        Spacer()

                        Text("\(progressSummary.progressPercent)%")
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(.accent)
                    }

                    GeometryReader { geometry in
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(.accent)
                                    .frame(width: geometry.size.width * progressSummary.progressFraction)
                            }
                    }
                    .frame(height: 10)

                    Text(progressSummary.progressText)
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.64))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Did you know?")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text(viewModel.climb.funFact)
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.74) : .black.opacity(0.66))
            }

            Button(action: handlePrimaryAction) {
                Text(viewModel.actionTitle)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(viewModel.isActionEnabled ? .black : .white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(viewModel.isActionEnabled ? Color.accent : .white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isActionEnabled)

            if viewModel.isCurrentActiveClimb {
                HStack(spacing: 12) {
                    if !showsBrowseBackButton {
                        secondaryActionButton(title: "Browse Other Climbs") {
                            browseViewModel.prepareForBrowseEntry()
                            showingBrowseClimbs = true
                        }
                    }

                    secondaryActionButton(title: "End Climb", role: .destructive) {
                        showingEndClimbConfirmation = true
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your History")
                .font(.montserratBold(size: 22))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            if viewModel.historySummary.recentEntries.isEmpty {
                Text("Attempts and completions for this climb will show up here.")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
            } else {
                HStack(spacing: 14) {
                    statCard(value: viewModel.historySummary.completionsCount.formatted(), label: "COMPLETIONS")

                    if let bestCompletionDurationSeconds = viewModel.historySummary.bestCompletionDurationSeconds {
                        statCard(
                            value: DurationFormatter.format(duration: TimeInterval(bestCompletionDurationSeconds)),
                            label: "BEST TIME"
                        )
                    } else {
                        statCard(value: viewModel.historySummary.attemptsCount.formatted(), label: "ATTEMPTS")
                    }
                }

                if viewModel.historySummary.failedAttemptsCount > 0 {
                    Text("Short one-workout attempts are saved here so you can retry without losing the effort.")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.54))
                }

                Text("RECENT ATTEMPTS")
                    .font(.montserratSemiBold(size: 12))
                    .tracking(1.2)
                    .foregroundStyle(Color.customGray)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(viewModel.historySummary.recentEntries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.montserratSemiBold(size: 15))
                                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                                    Text(historyRowSubtitle(for: entry))
                                        .font(.montserratRegular(size: 13))
                                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.5))
                                }

                                Spacer()

                                if entry.status == .failed {
                                    historyBadge(
                                        title: "ATTEMPT",
                                        foreground: .white.opacity(0.78),
                                        background: .white.opacity(0.08)
                                    )
                                } else if entry.isPersonalBest {
                                    historyBadge(
                                        title: "PR",
                                        foreground: Color(hex: "F3E58A"),
                                        background: Color(hex: "F3E58A").opacity(0.14)
                                    )
                                }

                                Text(DurationFormatter.format(duration: TimeInterval(entry.durationSeconds)))
                                    .font(.montserratBold(size: 18))
                                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            }
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.white.opacity(0.04))
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var leaderboardPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Leaderboard")
                .font(.montserratBold(size: 22))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text("Coming Soon")
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text("Landmark-specific leaderboards are planned, but this climb-first pass keeps everything private for now while the core progress loop ships.")
                .font(.montserratRegular(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    private func metricCell(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text(title)
                .font(.montserratSemiBold(size: 12))
                .tracking(1.0)
                .foregroundStyle(Color.customGray)
        }
        .frame(maxWidth: .infinity)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.montserratBold(size: 22))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text(label)
                .font(.montserratSemiBold(size: 12))
                .tracking(1.0)
                .foregroundStyle(Color.customGray)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.04))
        )
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

    private func historyRowSubtitle(for entry: ClimbHistoryEntry) -> String {
        switch entry.status {
        case .completed:
            return "\(entry.totalSteps.formatted()) steps"
        case .failed:
            return "\(entry.recordedSteps.formatted()) / \(entry.totalSteps.formatted()) steps"
        case .active, .abandoned:
            return "\(entry.recordedSteps.formatted()) steps"
        }
    }

    private func secondaryActionButton(
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(role == .destructive ? Color.red.opacity(0.86) : .white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
    }

    private func handlePrimaryAction() {
        if viewModel.isCurrentActiveClimb {
            showingWorkoutEntrySheet = true
            return
        }

        guard viewModel.isActionEnabled else { return }

        if viewModel.conflictingActiveSummary != nil {
            showingReplaceConfirmation = true
            return
        }

        do {
            try viewModel.startClimb(modelContext: modelContext)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func presentWorkoutForm() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showingWorkoutForm = true
        }
    }

    private func presentRoutines() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showingRoutinesView = true
        }
    }

    private func presentImportSheet() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await importCoordinator.refreshPendingImports(trigger: .manualReview)
            showingImportSheet = true
        }
    }
}

#Preview("Default") {
    NavigationStack {
        ClimbDetailView(climb: .preview, showsBrowseBackButton: true)
    }
    .preferredColorScheme(.dark)
}

#Preview("With Collection Strip") {
    NavigationStack {
        ClimbDetailView(climb: .preview, showsBrowseBackButton: true, initialCollectionOrder: 3)
    }
    .preferredColorScheme(.dark)
}
