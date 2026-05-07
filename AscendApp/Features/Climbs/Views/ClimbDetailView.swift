@preconcurrency import FirebaseAuth
import SwiftData
import SwiftUI

struct ClimbDetailView: View {
    let showsBrowseBackButton: Bool
    let analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint
    private let initialCollectionOrder: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var viewModel: ClimbDetailViewModel
    @State private var selectedPage = 0
    @State private var detailPageHeights: [Int: CGFloat] = [:]
    @State private var showingReplaceConfirmation = false
    @State private var showingEndClimbConfirmation = false
    @State private var showingBrowseClimbs = false
    @State private var showingLiveClimbSession = false
    @State private var liveSessionReplacesActiveClimb = false
    @State private var showingHeadphoneHelp = false
    @State private var isHeroCardFlipped = false
    @State private var didTrackDetailViewed = false
    @State private var browseViewModel = GlobeViewModel()
    @State private var headphoneMotionService = HeadphoneMotionReadinessService.shared
    @State private var actionErrorMessage: String?

    init(
        climb: Climb,
        showsBrowseBackButton: Bool = false,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown,
        initialCollectionOrder: Int? = nil
    ) {
        self.showsBrowseBackButton = showsBrowseBackButton
        self.analyticsEntryPoint = analyticsEntryPoint
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

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentBrowseFromDetail()
                } label: {
                    AppIcon(token: .globeHemisphereWest, pointSize: 23)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.78))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse climbs")
            }
        }
        .navigationDestination(isPresented: $showingBrowseClimbs) {
            ClimbBrowseView(viewModel: browseViewModel, analyticsEntryPoint: .detailBrowse)
        }
        .navigationDestination(isPresented: $showingLiveClimbSession) {
            LiveClimbSessionView(
                climb: viewModel.climb,
                replacingActiveClimb: liveSessionReplacesActiveClimb,
                analyticsEntryPoint: analyticsEntryPoint
            )
        }
        .sheet(isPresented: $showingHeadphoneHelp) {
            liveClimbHeadphoneHelpSheet
                .appSheetStyle(.fitted())
        }
        .confirmationDialog(
            "Replace Active Climb?",
            isPresented: $showingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Current Climb", role: .destructive) {
                liveSessionReplacesActiveClimb = true
                showingLiveClimbSession = true
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
            trackDetailViewedIfNeeded()
            headphoneMotionService.refresh()
            viewModel.refresh(modelContext: modelContext)
            if let initialCollectionOrder {
                viewModel.collectionOrder = initialCollectionOrder
            }
            await viewModel.refreshLeaderboardSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            headphoneMotionService.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
            Task {
                await viewModel.refreshLeaderboardSummary()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
            Task {
                await viewModel.refreshLeaderboardSummary()
            }
        }
    }

    private var heroCard: some View {
        let heroShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return ZStack {
            heroCardFace {
                heroCardFront
            }
                .opacity(isHeroCardFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isHeroCardFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )

            heroCardFace {
                heroCardBack
            }
                .opacity(isHeroCardFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isHeroCardFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )
        }
        .contentShape(heroShape)
        .onTapGesture {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                isHeroCardFlipped.toggle()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Flip the climb card")
    }

    private func heroCardFace<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let heroShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return content()
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

    private var heroCardFront: some View {
        ZStack(alignment: .bottomLeading) {
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
    }

    private var heroCardBack: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.96),
                    viewModel.climb.tier.color.opacity(0.18),
                    Color.black.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(viewModel.climb.tier.displayName) Tier")
                                .font(.montserratBold(size: 34))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Text(viewModel.climb.tier.stepRangeDescription)
                                .font(.montserratSemiBold(size: 14))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }

                    Spacer()
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 10) {
                    Text("LANDMARK FACT")
                        .font(.montserratSemiBold(size: 12))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.48))

                    Text(viewModel.climb.funFact)
                        .font(.montserratRegular(size: 17))
                        .foregroundStyle(.white)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(height: 1)
                }

                Text("Tap to flip back")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(24)
        }
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
        .animation(.smooth(duration: 0.25), value: selectedPage)
    }

    private var detailPages: some View {
        ZStack(alignment: .topLeading) {
            selectedDetailPageMeasurer

            TabView(selection: $selectedPage) {
                ForEach(0..<3, id: \.self) { pageIndex in
                    detailPageContent(for: pageIndex)
                        .tag(pageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: detailPageHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .onPreferenceChange(ClimbDetailPageHeightPreferenceKey.self) { heights in
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
                        key: ClimbDetailPageHeightPreferenceKey.self,
                        value: [selectedPage: geometry.size.height]
                    )
                }
            )
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var detailPageHeight: CGFloat {
        detailPageHeights[selectedPage] ?? detailPageHeights.values.max() ?? 320
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

    private var historyMetrics: [HistoryMetric] {
        var metrics = [
            HistoryMetric(
                id: "completions",
                value: viewModel.historySummary.completionsCount.formatted(),
                label: "COMPLETIONS"
            ),
            HistoryMetric(
                id: "attempts",
                value: viewModel.historySummary.attemptsCount.formatted(),
                label: "ATTEMPTS"
            )
        ]

        if let bestCompletionDurationSeconds = viewModel.historySummary.bestCompletionDurationSeconds {
            metrics.append(HistoryMetric(
                id: "best",
                value: DurationFormatter.format(duration: TimeInterval(bestCompletionDurationSeconds)),
                label: "BEST TIME"
            ))
        }

        if let averageCompletionDurationSeconds = viewModel.historySummary.averageCompletionDurationSeconds {
            metrics.append(HistoryMetric(
                id: "average",
                value: DurationFormatter.format(duration: TimeInterval(averageCompletionDurationSeconds)),
                label: "AVG TIME"
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

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            if viewModel.showsCommunityStats {
                communityStatsRow
            }

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

            primaryActionRow

            if viewModel.showsPersistentProgressControls {
                HStack(spacing: 12) {
                    if !showsBrowseBackButton {
                        secondaryActionButton(title: "Browse Other Climbs") {
                            presentBrowseFromDetail()
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your History")
                .font(.montserratBold(size: 22))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            if viewModel.historySummary.recentEntries.isEmpty {
                Text("Attempts and completions for this climb will show up here.")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
            } else {
                historyMetricsGrid
                    .padding(.vertical, 2)

                Text("RECENT ATTEMPTS")
                    .font(.montserratSemiBold(size: 12))
                    .tracking(1.2)
                    .foregroundStyle(Color.customGray)

                VStack(spacing: 0) {
                    ForEach(viewModel.historySummary.recentEntries) { entry in
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Leaderboard")
                        .font(.montserratBold(size: 22))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text("Fastest completion times")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.58))
                }

                Spacer(minLength: 0)

                if viewModel.completionLeaderboardCompletedCount > 0 {
                    Text("\(viewModel.completionLeaderboardCompletedCount.formatted()) completed")
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(.accent)
                        .monospacedDigit()
                }
            }

            if viewModel.isLeaderboardLoading && !viewModel.hasCompletionLeaderboardRows {
                leaderboardLoadingState
            } else if viewModel.hasCompletionLeaderboardRows {
                if viewModel.shouldShowPersonalRankSummary {
                    personalLeaderboardRankSummary
                }

                VStack(spacing: 0) {
                    ForEach(viewModel.completionLeaderboardRows) { row in
                        leaderboardRow(for: row)
                    }
                }
            } else {
                leaderboardEmptyState
            }

            if viewModel.leaderboardErrorMessage != nil,
               !viewModel.isLeaderboardLoading {
                Text("Leaderboard unavailable")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color.red.opacity(0.82))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var leaderboardLoadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.accent)

            Text("Loading leaderboard")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.64) : .black.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var leaderboardEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No completed times yet")
                .font(.montserratBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text("Complete this climb to put the first time on the board.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var personalLeaderboardRankSummary: some View {
        if let personalCompletionRank = viewModel.personalCompletionRank,
           let bestCompletionDurationSeconds = viewModel.historySummary.bestCompletionDurationSeconds {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your best")
                        .font(.montserratSemiBold(size: 12))
                        .tracking(1.0)
                        .foregroundStyle(Color.customGray)

                    Text(DurationFormatter.format(duration: TimeInterval(bestCompletionDurationSeconds)))
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("#\(personalCompletionRank.rank.formatted())")
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(.accent)
                        .monospacedDigit()

                    Text("of \(personalCompletionRank.completedCount.formatted())")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.5))
                        .monospacedDigit()
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accent.opacity(effectiveColorScheme == .dark ? 0.12 : 0.10))
            )
        }
    }

    private func leaderboardRow(for row: LiveReplayLeaderboardRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("#\(row.rank?.formatted() ?? "--")")
                .font(.montserratBold(size: 15))
                .foregroundStyle(row.isCurrentUser ? .accent : Color.customGray)
                .frame(width: 46, alignment: .leading)
                .monospacedDigit()

            leaderboardAvatar(for: row)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(row.isCurrentUser ? "You" : row.displayName)
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if row.isCurrentUser {
                        Text("YOU")
                            .font(.montserratBold(size: 9))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accent)
                            )
                    }
                }

                Text("\(row.finalSteps.formatted()) steps")
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.54) : .black.opacity(0.48))
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(leaderboardDurationText(for: row))
                    .font(.montserratBold(size: 17))
                    .foregroundStyle(row.isCurrentUser ? .accent : (effectiveColorScheme == .dark ? .white : .black))
                    .monospacedDigit()

                if let averageStepsPerMinute = row.averageStepsPerMinute {
                    Text("\(Int(averageStepsPerMinute.rounded()).formatted()) avg SPM")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.50) : .black.opacity(0.46))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, row.isCurrentUser ? 12 : 0)
        .background {
            if row.isCurrentUser {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accent.opacity(effectiveColorScheme == .dark ? 0.12 : 0.10))
            }
        }
        .overlay(alignment: .bottom) {
            if !row.isCurrentUser {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func leaderboardDurationText(for row: LiveReplayLeaderboardRow) -> String {
        guard let completionDurationSeconds = row.completionDurationSeconds else {
            return "--"
        }

        return DurationFormatter.format(duration: completionDurationSeconds)
    }

    @ViewBuilder
    private func leaderboardAvatar(for row: LiveReplayLeaderboardRow) -> some View {
        if let photoURL = row.isCurrentUser ? (row.photoURL ?? currentUserPhotoURL) : row.photoURL {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    leaderboardAvatarToken(for: row)
                @unknown default:
                    leaderboardAvatarToken(for: row)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(row.isCurrentUser ? Color.accent : .white.opacity(0.14), lineWidth: row.isCurrentUser ? 2 : 1)
            )
            .id(photoURL)
        } else {
            leaderboardAvatarToken(for: row)
        }
    }

    private func leaderboardAvatarToken(for row: LiveReplayLeaderboardRow) -> some View {
        Text(row.isCurrentUser ? currentUserAvatar.token : row.avatarToken)
            .font(.montserratBold(size: 13))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(row.isCurrentUser ? Color.accent : communityAvatarColor(for: row.id))
            )
            .overlay(
                Circle()
                    .stroke(row.isCurrentUser ? Color.accent.opacity(0.7) : .white.opacity(0.14), lineWidth: 1)
            )
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

    private var communityStatsRow: some View {
        HStack(alignment: .center, spacing: 14) {
            communityAvatarStack
                .layoutPriority(1)

            communityCaption
                .layoutPriority(2)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(communityAccessibilityLabel)
    }

    @ViewBuilder
    private var communityAvatarStack: some View {
        if !visibleCommunityAvatars.isEmpty {
            HStack(spacing: -10) {
                ForEach(visibleCommunityAvatars) { avatar in
                    ClimbCommunityAvatarView(
                        avatar: avatar,
                        effectiveColorScheme: effectiveColorScheme
                    )
                }
            }
            .frame(height: 44)
        }
    }

    private var communityCaption: some View {
        Group {
            if viewModel.communityCompletedCount == 0 {
                Text("Be the first to complete this climb")
                    .font(.montserratRegular(size: 17))
                    .foregroundStyle(communitySecondaryColor)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(viewModel.communityCompletedCount.formatted())
                        .font(.montserratBold(size: 17))
                        .foregroundStyle(.accent)
                        .monospacedDigit()

                    Text(" completed")
                        .font(.montserratRegular(size: 17))
                        .foregroundStyle(communitySecondaryColor)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private var communityAccessibilityLabel: String {
        if viewModel.communityCompletedCount == 0 {
            return "Be the first to complete this climb"
        }
        return "\(viewModel.communityCompletedCount) completed"
    }

    private var visibleCommunityAvatars: [ClimbCommunityAvatar] {
        let currentState = currentUserCommunityState
        let remoteLimit = currentState == nil ? 3 : 2
        let currentToken = currentUserAvatar.token
        let currentDisplayName = currentUserDisplayName
        var avatars: [ClimbCommunityAvatar] = []

        if let currentState {
            avatars.append(currentUserAvatar(style: currentState))
        }

        let remoteAvatars = viewModel.leaderboardPreviewRows
            .filter { row in
                guard currentState != nil else { return true }
                let displayNamesMatch = !currentDisplayName.isEmpty &&
                    row.displayName.compare(currentDisplayName, options: .caseInsensitive) == .orderedSame
                return row.avatarToken != currentToken && !displayNamesMatch
            }
            .prefix(remoteLimit)
            .map(communityAvatar)

        avatars.append(contentsOf: remoteAvatars)
        return Array(avatars.prefix(3))
    }

    private var currentUserCommunityState: ClimbCommunityAvatar.Style? {
        if viewModel.hasCompletionHistory {
            return .currentCompleted
        }

        if viewModel.hasIncompleteAttemptHistory {
            return .currentAttempted
        }

        return nil
    }

    private var currentUserAvatar: ClimbCommunityAvatar {
        currentUserAvatar(style: .regular)
    }

    private func currentUserAvatar(style: ClimbCommunityAvatar.Style) -> ClimbCommunityAvatar {
        ClimbCommunityAvatar(
            id: "current-user",
            token: Self.avatarToken(for: currentUserDisplayName),
            photoURL: currentUserPhotoURL,
            backgroundColor: Color(red: 0.22, green: 0.72, blue: 0.68),
            style: style
        )
    }

    private var currentUserDisplayName: String {
        let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedDisplayName, !cachedDisplayName.isEmpty {
            return cachedDisplayName
        }

        let authDisplayName = Auth.auth().currentUser?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let authDisplayName, !authDisplayName.isEmpty {
            return authDisplayName
        }

        return "You"
    }

    private var currentUserPhotoURL: URL? {
        if let cachedURL = UserDataRepository.shared.getCachedProfilePictureURL()
            .flatMap(URL.init(string:)) {
            return cachedURL
        }

        return Auth.auth().currentUser?.photoURL
    }

    private func communityAvatar(for row: LiveReplayLeaderboardRow) -> ClimbCommunityAvatar {
        ClimbCommunityAvatar(
            id: row.id,
            token: row.avatarToken,
            photoURL: row.photoURL,
            backgroundColor: communityAvatarColor(for: row.id),
            style: .regular
        )
    }

    private func communityAvatarColor(for id: String) -> Color {
        let colors: [Color] = [
            Color(red: 0.94, green: 0.33, blue: 0.43),
            Color(red: 0.21, green: 0.72, blue: 0.69),
            Color(red: 1.0, green: 0.57, blue: 0.08),
            Color(red: 0.40, green: 0.34, blue: 0.86)
        ]
        return colors[Int(id.hashValue.magnitude % UInt(colors.count))]
    }

    private var communityPrimaryColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var communitySecondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.58)
    }

    private static func avatarToken(for displayName: String) -> String {
        let token = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()

        return token.isEmpty ? "YOU" : token
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

    private func historyRow(for entry: ClimbHistoryEntry) -> some View {
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

            if entry.status == .failed {
                historyBadge(
                    title: "ATTEMPT",
                    foreground: .white.opacity(0.72),
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

    private var primaryActionRow: some View {
        HStack(spacing: 10) {
            Button(action: handlePrimaryAction) {
                Text(primaryActionTitle)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(isPrimaryActionEnabled ? .black : .white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isPrimaryActionEnabled ? Color.accent : .white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isPrimaryActionEnabled)

            Button {
                showingHeadphoneHelp = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.68))
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Live climb headphone help")
        }
    }

    private var primaryActionTitle: String {
        viewModel.actionTitle
    }

    private var isPrimaryActionEnabled: Bool {
        viewModel.isActionEnabled && headphoneMotionService.readiness.canStartLiveClimb
    }

    private var liveClimbHeadphoneHelpSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Compatible Headphones")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("Ascend uses headphone motion to track steps in real time during Live Climbs.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            compatibleHeadphoneGroup(
                title: "AirPods",
                headphones: [
                    "AirPods 3",
                    "AirPods 4",
                    "AirPods 4 with Active Noise Cancellation",
                    "AirPods Pro 1",
                    "AirPods Pro 2",
                    "AirPods Pro 3",
                    "AirPods Max"
                ]
            )

            compatibleHeadphoneGroup(
                title: "Beats",
                headphones: [
                    "Beats Fit Pro",
                    "Beats Studio Pro",
                    "Beats Solo 4",
                    "Powerbeats Pro 2",
                    "Powerbeats Fit"
                ]
            )

            Link(destination: Self.appleHeadphoneCompatibilityURL) {
                Text("Don't see yours? Check Apple's current list.")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 10)
        .appSheetBackground()
    }

    private func compatibleHeadphoneGroup(title: String, headphones: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.montserratSemiBold(size: 11))
                .tracking(1.1)
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.48))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(headphones, id: \.self) { headphone in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(.accent)
                            .frame(width: 5, height: 5)

                        Text(headphone)
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.76) : .black.opacity(0.66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
        }
    }

    private static let appleHeadphoneCompatibilityURL = URL(string: "https://support.apple.com/en-us/102596")!

    private func handlePrimaryAction() {
        let canStart = headphoneMotionService.readiness.canStartLiveClimb
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.detailStartTapped(
                climb: viewModel.climb,
                entryPoint: analyticsEntryPoint,
                actionState: startActionState,
                canStart: canStart
            )
        )

        guard headphoneMotionService.readiness.canStartLiveClimb else {
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.detailStartBlocked(
                    climb: viewModel.climb,
                    entryPoint: analyticsEntryPoint,
                    reason: .headphonesUnavailable
                )
            )
            actionErrorMessage = "Live climb attempts require compatible headphones."
            return
        }

        if viewModel.isCurrentActiveClimb {
            liveSessionReplacesActiveClimb = false
            showingLiveClimbSession = true
            return
        }

        guard viewModel.isActionEnabled else { return }

        if viewModel.conflictingActiveSummary != nil {
            showingReplaceConfirmation = true
            return
        }

        liveSessionReplacesActiveClimb = false
        showingLiveClimbSession = true
    }

    private var startActionState: LiveClimbAnalyticsEvent.StartActionState {
        guard viewModel.isActionEnabled else { return .disabled }
        if viewModel.isCurrentActiveClimb {
            return .resumeActive
        }
        if viewModel.conflictingActiveSummary != nil {
            return .replaceActive
        }
        return .newAttempt
    }

    private func presentBrowseFromDetail() {
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.detailBrowseTapped(climb: viewModel.climb)
        )
        browseViewModel.prepareForBrowseEntry()
        showingBrowseClimbs = true
    }

    private func trackDetailViewedIfNeeded() {
        guard !didTrackDetailViewed else { return }
        didTrackDetailViewed = true
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.detailViewed(
                climb: viewModel.climb,
                entryPoint: analyticsEntryPoint
            )
        )
    }

}

private struct ClimbCommunityAvatar: Identifiable {
    enum Style {
        case regular
        case currentCompleted
        case currentAttempted
    }

    let id: String
    let token: String
    let photoURL: URL?
    let backgroundColor: Color
    let style: Style
}

private struct HistoryMetric: Identifiable {
    let id: String
    let value: String
    let label: String
}

private struct ClimbDetailPageHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, newValue in newValue }
    }
}

private struct ClimbCommunityAvatarView: View {
    let avatar: ClimbCommunityAvatar
    let effectiveColorScheme: ColorScheme

    @State private var isPulsing = false

    var body: some View {
        avatarContent
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay {
                borderOverlay
            }
            .shadow(
                color: glowColor,
                radius: glowRadius,
                x: 0,
                y: 0
            )
            .scaleEffect(avatar.style == .currentAttempted && isPulsing ? 1.035 : 1)
            .onAppear {
                guard avatar.style == .currentAttempted else { return }
                withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let photoURL = avatar.photoURL {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    tokenContent
                @unknown default:
                    tokenContent
                }
            }
        } else {
            tokenContent
        }
    }

    private var tokenContent: some View {
        Text(avatar.token)
            .font(.montserratBold(size: 13))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Circle().fill(avatar.backgroundColor))
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch avatar.style {
        case .regular:
            Circle()
                .stroke(effectiveColorScheme == .dark ? .black.opacity(0.3) : .white.opacity(0.8), lineWidth: 2)
        case .currentCompleted:
            Circle()
                .stroke(Color.accent, lineWidth: 2.5)
                .padding(1.5)
        case .currentAttempted:
            Circle()
                .stroke(
                    Color.accent,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [5, 3])
                )
                .padding(1.4)
        }
    }

    private var glowColor: Color {
        switch avatar.style {
        case .currentCompleted:
            return Color.accent.opacity(0.48)
        case .currentAttempted:
            return Color.accent.opacity(isPulsing ? 0.46 : 0.18)
        case .regular:
            return .clear
        }
    }

    private var glowRadius: CGFloat {
        switch avatar.style {
        case .currentCompleted:
            return 6
        case .currentAttempted:
            return isPulsing ? 7 : 3
        case .regular:
            return 0
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
