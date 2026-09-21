//
//  HomeView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI
import SwiftData

/// Home is the globe.
///
/// The realistic globe fills the tab and opens at continent altitude centred on
/// Today's Climb. Over it sits a sheet with three positions, collapsed by default to
/// the This Week line; pulled up it carries the Today's Climb row, ON THE GLOBE TODAY,
/// the Weekly Rank and Streak tiles, Recent Personal Records, and then the catalog
/// browse sections with search. A tapped pin shows a card that opens Climb Detail.
///
/// Only the active tab is mounted, so the map renderer runs on Home alone, and every
/// `.task` here is bounded: the today feed is one listener on one document, the card
/// counts are two reads for one climb, and the catalog and dashboard refreshes are
/// the bounded queries the previous Home already ran.
struct HomeView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(ModerationStore.self) private var moderationStore
    // Passed directly rather than read from the environment: HomeView updates
    // during the onboarding -> main-app crossfade while briefly detached from
    // its environment, and a non-optional @Environment(TabRouter.self) read
    // fatal-errors there (ASCEND-IOS-13). MainTabView owns the router and
    // constructs this view, so direct injection is also the simpler shape.
    private let tabRouter: TabRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tabBarOverlayHeight) private var tabBarOverlayHeight
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var enrichmentService = AppleHealthEnrichmentService.shared
    private let homeDashboard: HomeDashboardViewModel
    @State private var todayActivity: HomeTodayActivityViewModel
    @State private var globeViewModel = GlobeViewModel()
    @State private var showingStartActionSheet = false
    @State private var showingHelpSheet = false
    @State private var showingJustClimbSetup = false
    @State private var pendingStartAction: HomeStartAction?
    @State private var pendingJustClimbGoal: JustClimbGoal?
    @State private var selectedDetailClimb: Climb?
    @State private var selectedDetailEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown
    @State private var activeJustClimbGoal: JustClimbGoal?
    @State private var showingTodayActivityList = false
    @State private var sheetDetent: BrowseSheetDetent
    @State private var selectedStepTier: ClimbTier?
    @State private var isSearchMode = false
    @State private var searchFocusTask: Task<Void, Never>?
    @State private var hasPreparedHomeEntry = false
    @State private var todayPresentations: [String: HomeTodayActivityRowPresentation] = [:]
    @FocusState private var isSearchFocused: Bool
    @AppStorage("firstLaunchDate") private var firstLaunchDate: Double = 0

    private let titleResolver = HomeTodayActivityTitleResolver()

    /// `initialSheetDetent` is `.compact` in the app: Home opens collapsed to the This
    /// Week line. The evidence suite hosts the other two positions directly.
    init(
        homeDashboard: HomeDashboardViewModel = HomeDashboardViewModel(),
        tabRouter: TabRouter,
        todayActivity: HomeTodayActivityViewModel = HomeTodayActivityViewModel(),
        initialSheetDetent: BrowseSheetDetent = .compact
    ) {
        self.homeDashboard = homeDashboard
        self.tabRouter = tabRouter
        _todayActivity = State(initialValue: todayActivity)
        _sheetDetent = State(initialValue: initialSheetDetent)
    }

    var body: some View {
        GeometryReader { safeAreaGeometry in
            let safeAreaInsets = safeAreaGeometry.safeAreaInsets
            // The tab bar is not in the safe area the tab content sees, so the sheet
            // measures its resting heights from the bar's top, not the home indicator.
            let bottomInset = safeAreaInsets.bottom + tabBarOverlayHeight

            GeometryReader { geometry in
                let topCoverageInset = max(0, geometry.frame(in: .global).minY)
                let sheetVisibleHeight = sheetDetent.height(
                    containerHeight: geometry.size.height,
                    topCoverageInset: topCoverageInset,
                    topInset: safeAreaInsets.top,
                    bottomInset: bottomInset
                )

                ZStack {
                    GlobeView(
                        viewModel: globeViewModel,
                        onSelectClimb: { climb in
                            selectGlobePin(climb)
                        }
                    )
                    .ignoresSafeArea()
                    .offset(y: globeVerticalOffset(sheetHeight: sheetVisibleHeight))

                    GlobeEdgeOverlays()

                    if globeViewModel.visibleClimbs.isEmpty {
                        ClimbCatalogStateOverlay(loadErrorMessage: globeViewModel.loadErrorMessage)
                    }

                    topChrome(topInset: safeAreaInsets.top)

                    previewCardArea(sheetHeight: sheetVisibleHeight)
                        .zIndex(2)

                    if !isSearchMode {
                        homeDrawer(
                            containerHeight: geometry.size.height,
                            topCoverageInset: topCoverageInset,
                            topInset: safeAreaInsets.top,
                            bottomInset: bottomInset
                        )
                        .zIndex(3)
                    }

                    if isSearchMode {
                        searchOverlay(
                            topInset: safeAreaInsets.top,
                            bottomInset: bottomInset
                        )
                        .zIndex(4)
                        .transition(.opacity)
                    }
                }
                .ignoresSafeArea()
                .ignoresSafeArea(.keyboard)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedDetailClimb) { climb in
            ClimbDetailView(climb: climb, analyticsEntryPoint: selectedDetailEntryPoint)
        }
        .navigationDestination(item: $activeJustClimbGoal) { goal in
            LiveClimbSessionView(
                justClimbGoal: goal,
                analyticsEntryPoint: .homeDaily
            )
        }
        .navigationDestination(isPresented: $showingTodayActivityList) {
            HomeTodayActivityListView(
                rows: moderatedTodayRows(allRows: true),
                presentations: todayPresentations,
                onOpen: { row, presentation in
                    openTodayRow(row, presentation: presentation)
                }
            )
        }
        .sheet(isPresented: $showingStartActionSheet, onDismiss: {
            consumePendingStartAction()
        }) {
            HomeStartActionSheet { action in
                pendingStartAction = action
                showingStartActionSheet = false
            }
            .appSheetStyle(.fitted())
        }
        .sheet(isPresented: $showingJustClimbSetup, onDismiss: {
            pendingJustClimbGoal = nil
        }) {
            JustClimbSetupSheet(initialGoal: pendingJustClimbGoal) { goal in
                activeJustClimbGoal = goal
            }
            .presentationDetents([.height(360), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.black)
        }
        .sheet(isPresented: $showingHelpSheet) {
            ClimbBrowseHelpSheet()
                .appSheetStyle(.fraction(0.8))
        }
        .task {
            // Set first launch date if not already set
            if firstLaunchDate == 0 {
                firstLaunchDate = Date().timeIntervalSince1970
            }

            enrichmentService.configure(modelContext: modelContext)
            globeViewModel.loadIfNeeded(modelContext: modelContext)
            prepareHomeEntryIfNeeded()
            refreshHomeDashboard(forceRank: true)
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()

            // Apple Health writes a climb's heart rate after the climb ends, so every Home entry
            // is another chance for a recent climb to pick up what was not there yet.
            await enrichmentService.refreshPendingEnrichment(modelContext: modelContext)
        }
        .task(id: authVM.user?.uid) {
            // One listener on one document, for as long as Home is mounted and this
            // climber is signed in. Cancelled with the tab, which removes the listener.
            await todayActivity.observe(currentUserId: authVM.user?.uid)
        }
        .task(id: globeViewModel.previewSummary?.climb.id) {
            await globeViewModel.refreshPreviewCounts()
        }
        .onChange(of: todayActivity.feed) { _, _ in
            refreshTodayPresentations()
        }
        .onChange(of: tabRouter.selectedTab) { _, newValue in
            guard newValue == .home else { return }
            refreshHomeDashboard()
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()
            Task {
                await enrichmentService.refreshPendingEnrichment(modelContext: modelContext)
            }
        }
        .onChange(of: authVM.user?.uid) { _, _ in
            refreshHomeDashboard(forceRank: true)
            refreshTodayClimbStake()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutsDidChange)) { _ in
            refreshHomeDashboard(forceRank: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshHomeDashboard(forceRank: true)
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()
            refreshTodayPresentations()
            Task {
                await enrichmentService.refreshPendingEnrichment(modelContext: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            globeViewModel.refresh(modelContext: modelContext)
            refreshHomeDashboard()
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            globeViewModel.reloadCatalog(modelContext: modelContext)
            refreshHomeDashboard()
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()
            refreshTodayPresentations()
        }
        .onDisappear {
            searchFocusTask?.cancel()
        }
    }

    // MARK: - Layout

    private func globeVerticalOffset(sheetHeight: CGFloat) -> CGFloat {
        switch sheetDetent {
        case .compact:
            return 0
        case .medium, .expanded:
            return -min(max(sheetHeight * 0.25, 64), 96)
        }
    }

    private func topChrome(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    AscendWordmark(size: 16, letterColor: .white)
                        .padding(.top, 12)

                    if !globeViewModel.mapScene.legendTiers.isEmpty {
                        ClimbStepRangeLegendView(tiers: globeViewModel.mapScene.legendTiers)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    GlobeControlButton(
                        systemName: "questionmark",
                        accessibilityLabel: "How Live Climbs work"
                    ) {
                        TelemetryManager.shared.track(LiveClimbAnalyticsEvent.browseHelpOpened)
                        showingHelpSheet = true
                    }
                    .accessibilityHint("Open help for climb tiers, map icons, and progress rules")

                    GlobeControlButton(
                        systemName: "plus",
                        accessibilityLabel: "Start",
                        fill: Color.accent,
                        foreground: .black
                    ) {
                        showingStartActionSheet = true
                    }
                    .accessibilityHint("Open climb actions")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, topInset + 10)

            Spacer()
        }
    }

    // MARK: - Sheet

    private func homeDrawer(
        containerHeight: CGFloat,
        topCoverageInset: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        ClimbBrowseDrawer(
            detent: $sheetDetent,
            containerHeight: containerHeight,
            topCoverageInset: topCoverageInset,
            topInset: topInset,
            bottomInset: bottomInset,
            dragDetents: [.compact, .medium, .expanded],
            accessibilityLabel: "Home sheet",
            accessibilityHint: "Drag to see this week, today's climbs and every climb on the globe",
            setDetent: { detent in
                setSheetDetent(detent)
            }
        ) {
            sheetContent(bottomInset: bottomInset)
        }
    }

    private func sheetContent(bottomInset: CGFloat) -> some View {
        VStack(spacing: 14) {
            HomeThisWeekLine(workouts: workouts)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    // Starts just below the collapsed fold, so nothing peeks under the
                    // This Week line until the sheet is pulled up.
                    Color.clear
                        .frame(height: 2)

                    if let todayClimb = globeViewModel.dailyRecommendedClimb {
                        HomeTodayClimbRow(
                            climb: todayClimb,
                            stakeLine: globeViewModel.todayClimbStakeLine,
                            isCompleted: globeViewModel.isCompleted(todayClimb)
                        ) {
                            openTodayClimb(todayClimb)
                        }
                    }

                    HomeTodayActivitySection(
                        rows: moderatedTodayRows(allRows: false),
                        presentations: todayPresentations,
                        showsSeeAll: todayActivity.showsSeeAll,
                        onOpen: { row, presentation in
                            openTodayRow(row, presentation: presentation)
                        },
                        onSeeAll: {
                            showingTodayActivityList = true
                        }
                    )

                    HomeRankStreakSection(
                        weeklyRankSummary: homeDashboard.weeklyRankSummary,
                        isRankLoading: homeDashboard.isRankLoading,
                        currentStreakWeeks: Workout.calculateWeeklyStreak(from: workouts),
                        onRankTapped: { tabRouter.select(.leaderboard, reason: .homeRankCard) },
                        onStreakTapped: { tabRouter.select(.profile, reason: .appRouting) }
                    )

                    if !homeDashboard.recentPersonalRecords.isEmpty {
                        HomeRecentPRsSection(
                            records: homeDashboard.recentPersonalRecords,
                            workouts: workouts
                        )
                    }

                    browseContent
                }
                .padding(.bottom, bottomInset + 22)
            }
            .scrollDisabled(sheetDetent != .expanded)
        }
        .padding(.horizontal, 16)
    }

    /// The catalog, as Browse lists it, at the end of the sheet. Search lives here
    /// too, in the expanded position.
    private var browseContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sheetDetent == .expanded {
                // Exists only while the sheet is expanded, so each expansion reports
                // itself once and a collapsed sheet reports nothing.
                Color.clear
                    .frame(height: 0)
                    .trackOnce(screen: .homeSheetExpanded)
            }

            ClimbSearchLauncher(viewModel: globeViewModel) {
                enterSearchMode()
            }

            browseSections
        }
    }

    private var browseSections: some View {
        ClimbBrowseSectionsView(
            viewModel: globeViewModel,
            selectedStepTier: $selectedStepTier,
            showsTodaysClimb: false,
            onOpenClimb: { climb, source in
                openClimbFromSheet(climb, source: source)
            },
            onExpand: {
                setSheetDetent(.expanded)
            }
        )
    }

    private func searchOverlay(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ClimbSearchField(viewModel: globeViewModel, isFocused: $isSearchFocused)

                Button("Cancel") {
                    exitSearchMode(clearQuery: true)
                }
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.top, topInset + 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if isSearching {
                        ClimbSearchResultsView(viewModel: globeViewModel) { climb in
                            openClimbFromSheet(climb, source: .browseSearch)
                        }
                    } else {
                        browseSections
                    }
                }
                .padding(.bottom, bottomInset + 22)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Card

    private func previewCardArea(sheetHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()

            if let previewSummary = globeViewModel.previewSummary {
                ClimbPreviewCardView(
                    summary: previewSummary,
                    counts: globeViewModel.previewCounts,
                    onSelect: {
                        openPreviewClimb(previewSummary.climb)
                    },
                    onClose: {
                        globeViewModel.dismissPreview()
                        setSheetDetent(.compact)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, sheetHeight + 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .trackOnce(screen: .homeClimbCard)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: globeViewModel.previewSummary?.climb.id)
    }

    // MARK: - Today rows

    private func moderatedTodayRows(allRows: Bool) -> [ModeratedHomeTodayActivityRow] {
        moderationStore.moderate(allRows ? todayActivity.allRows : todayActivity.homeRows)
    }

    private func refreshTodayPresentations() {
        let rows = moderatedTodayRows(allRows: true)
        todayPresentations = titleResolver.presentations(for: rows, modelContext: modelContext)
    }

    private func openTodayRow(
        _ row: ModeratedHomeTodayActivityRow,
        presentation: HomeTodayActivityRowPresentation
    ) {
        switch presentation.destination {
        case .climbDetail(let climbId):
            guard let climb = try? ClimbService.shared.climb(for: climbId), climb.isAvailable else { return }
            showingTodayActivityList = false
            openClimbDetail(climb, entryPoint: .homeTodayRow)
        case .justClimb(let goal):
            pendingJustClimbGoal = goal
            showingTodayActivityList = false
            showingJustClimbSetup = true
        case .routineTemplate(let templateId):
            showingTodayActivityList = false
            tabRouter.openRoutineTemplate(templateId)
        case .none:
            break
        }
    }

    // MARK: - Actions

    private func prepareHomeEntryIfNeeded() {
        guard !hasPreparedHomeEntry else { return }
        hasPreparedHomeEntry = true
        globeViewModel.prepareForHomeEntry()
    }

    private func selectGlobePin(_ climb: Climb) {
        exitSearchMode(clearQuery: true, targetDetent: .compact)
        isSearchFocused = false
        globeViewModel.clearSearch()
        globeViewModel.selectPreview(climb, modelContext: modelContext)
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.browsePreviewShown(climb: climb)
        )
        setSheetDetent(.compact)
    }

    private func openTodayClimb(_ climb: Climb) {
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.homeDailyTapped(
                climb: climb,
                homeState: globeViewModel.homeCardState
            )
        )
        openClimbDetail(climb, entryPoint: .homeDaily)
    }

    private func openClimbFromSheet(
        _ climb: Climb,
        source: LiveClimbAnalyticsEvent.EntryPoint
    ) {
        guard climb.isAvailable else { return }

        exitSearchMode(clearQuery: false, targetDetent: .medium)
        globeViewModel.previewSummary = nil
        globeViewModel.userDidInteract()
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.browseClimbOpened(
                climb: climb,
                entryPoint: source
            )
        )
        openClimbDetail(climb, entryPoint: source)
    }

    private func openPreviewClimb(_ climb: Climb) {
        guard climb.isAvailable else { return }

        exitSearchMode(clearQuery: false, targetDetent: .compact)
        globeViewModel.userDidInteract()
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.browseClimbOpened(
                climb: climb,
                entryPoint: .homeCard
            )
        )
        openClimbDetail(climb, entryPoint: .homeCard)
    }

    private func openClimbDetail(_ climb: Climb, entryPoint: LiveClimbAnalyticsEvent.EntryPoint) {
        selectedDetailEntryPoint = entryPoint
        selectedDetailClimb = climb
    }

    private func consumePendingStartAction() {
        guard let action = pendingStartAction else { return }
        pendingStartAction = nil

        switch action {
        case .justClimb:
            pendingJustClimbGoal = nil
            showingJustClimbSetup = true
        case .browseClimbs:
            // The globe is already here: the sheet's expanded position is the list.
            setSheetDetent(.expanded)
        case .routines:
            tabRouter.select(.training, reason: .appRouting)
        }
    }

    private func setSheetDetent(
        _ detent: BrowseSheetDetent,
        dismissKeyboard: Bool = true
    ) {
        if dismissKeyboard, detent != .expanded {
            isSearchFocused = false
        }
        if detent != .compact {
            globeViewModel.previewSummary = nil
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            sheetDetent = detent
        }
        globeViewModel.userDidInteract()
    }

    private func enterSearchMode() {
        searchFocusTask?.cancel()

        if globeViewModel.previewSummary != nil {
            globeViewModel.dismissPreview()
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            isSearchMode = true
        }
        globeViewModel.userDidInteract()

        searchFocusTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, isSearchMode else { return }
            isSearchFocused = true
        }
    }

    private func exitSearchMode(
        clearQuery: Bool,
        targetDetent: BrowseSheetDetent = .expanded
    ) {
        searchFocusTask?.cancel()
        searchFocusTask = nil
        isSearchFocused = false

        if clearQuery {
            globeViewModel.clearSearch()
        }

        guard isSearchMode else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            isSearchMode = false
            sheetDetent = targetDetent
        }
        globeViewModel.userDidInteract()
    }

    private var isSearching: Bool {
        !globeViewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func refreshLiveClimbCommunityStats() {
        Task {
            await globeViewModel.refreshLiveClimbCommunityStats()
        }
    }

    private func refreshTodayClimbStake() {
        Task {
            await globeViewModel.refreshTodayClimbStake(
                modelContext: modelContext,
                currentUserId: authVM.user?.uid
            )
        }
    }

    private func refreshHomeDashboard(forceRank: Bool = false) {
        homeDashboard.refreshLocalData(modelContext: modelContext)
        homeDashboard.refreshWeeklyRank(
            userId: authVM.user?.uid,
            displayName: authVM.displayName,
            photoURL: authVM.customProfilePictureURL ?? authVM.photoURL,
            modelContext: modelContext,
            forceRemote: forceRank
        )
    }
}

#Preview {
    NavigationStack {
        HomeView(tabRouter: TabRouter())
            .environment(AuthenticationViewModel())
            .environment(ModerationStore.shared)
    }
    .modelContainer(
        for: [
            Workout.self,
            WorkoutSourceLink.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        ],
        inMemory: true
    )
}
