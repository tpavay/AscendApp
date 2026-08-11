//
//  HomeView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    // Passed directly rather than read from the environment: HomeView updates
    // during the onboarding -> main-app crossfade while briefly detached from
    // its environment, and a non-optional @Environment(TabRouter.self) read
    // fatal-errors there (ASCEND-IOS-13). MainTabView owns the router and
    // constructs this view, so direct injection is also the simpler shape.
    private let tabRouter: TabRouter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var enrichmentService = AppleHealthEnrichmentService.shared
    private let homeDashboard: HomeDashboardViewModel
    @State private var showingStartActionSheet = false
    @State private var showingClimbBrowse = false
    @State private var showingJustClimbSetup = false
    @State private var pendingStartAction: HomeStartAction?
    @State private var selectedHomeClimb: Climb?
    @State private var activeJustClimbGoal: JustClimbGoal?
    @State private var globeViewModel = GlobeViewModel()
    @AppStorage("firstLaunchDate") private var firstLaunchDate: Double = 0

    init(
        homeDashboard: HomeDashboardViewModel = HomeDashboardViewModel(),
        tabRouter: TabRouter
    ) {
        self.homeDashboard = homeDashboard
        self.tabRouter = tabRouter
    }

    private var greeting: String {
        // If first launch date not set, this is the first launch
        if firstLaunchDate == 0 {
            return "Welcome"
        }

        let firstDate = Date(timeIntervalSince1970: firstLaunchDate)
        let isFirstDay = Calendar.current.isDate(firstDate, inSameDayAs: Date())

        if isFirstDay {
            return "Welcome"
        }

        // Time-based greeting
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    private var greetingWithName: String {
        if authVM.displayName.isEmpty {
            return greeting
        }
        // Use just the first name (first part before space)
        let firstName = authVM.displayName.split(separator: " ").first.map(String.init) ?? authVM.displayName
        return "\(greeting), \(firstName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                AscendWordmark(
                    size: 16,
                    letterColor: colorScheme == .dark ? .white : .black
                )

                Spacer()

                startHeaderButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 20) {
                    TodayHomeSectionView(
                        viewModel: globeViewModel,
                        onOpenClimb: { climb in
                            TelemetryManager.shared.track(
                                LiveClimbAnalyticsEvent.homeDailyTapped(
                                    climb: climb,
                                    homeState: globeViewModel.homeCardState
                                )
                            )
                            selectedHomeClimb = climb
                        }
                    )

                    HomeRankGlobeSection(
                        weeklyRankSummary: homeDashboard.weeklyRankSummary,
                        isRankLoading: homeDashboard.isRankLoading,
                        completedClimbCount: homeDashboard.completedClimbCount,
                        totalClimbCount: globeViewModel.climbCount,
                        onRankTapped: { tabRouter.selectedTab = .leaderboard },
                        onGlobeTapped: { presentClimbBrowse() }
                    )

                    if !homeDashboard.recentPersonalRecords.isEmpty {
                        HomeRecentPRsSection(
                            records: homeDashboard.recentPersonalRecords,
                            workouts: workouts
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 124)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaPadding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .themedBackground()
        .navigationDestination(item: $selectedHomeClimb) { climb in
            ClimbDetailView(climb: climb, analyticsEntryPoint: .homeDaily)
        }
        .navigationDestination(item: $activeJustClimbGoal) { goal in
            LiveClimbSessionView(
                justClimbGoal: goal,
                analyticsEntryPoint: .homeDaily
            )
        }
        .navigationDestination(isPresented: $showingClimbBrowse) {
            ClimbBrowseView(viewModel: globeViewModel, analyticsEntryPoint: .homeExplore)
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
        .sheet(isPresented: $showingJustClimbSetup) {
            JustClimbSetupSheet { goal in
                activeJustClimbGoal = goal
            }
            .presentationDetents([.height(360), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.black)
        }
        .task {
            // Set first launch date if not already set
            if firstLaunchDate == 0 {
                firstLaunchDate = Date().timeIntervalSince1970
            }

            enrichmentService.configure(modelContext: modelContext)
            globeViewModel.loadIfNeeded(modelContext: modelContext)
            refreshHomeDashboard(forceRank: true)
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()

            // Apple Health writes a climb's heart rate after the climb ends, so every Home entry
            // is another chance for a recent climb to pick up what was not there yet.
            await enrichmentService.refreshPendingEnrichment(modelContext: modelContext)
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
        }
    }

    private var startHeaderButton: some View {
        Button {
            showingStartActionSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(Color.accent)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start")
        .accessibilityHint("Open climb actions")
    }

    private func presentClimbBrowse() {
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.homeExploreTapped(
                totalClimbs: globeViewModel.climbCount
            )
        )
        globeViewModel.prepareForBrowseEntry()
        showingClimbBrowse = true
    }

    private func consumePendingStartAction() {
        guard let action = pendingStartAction else { return }
        pendingStartAction = nil

        switch action {
        case .justClimb:
            showingJustClimbSetup = true
        case .browseClimbs:
            presentClimbBrowse()
        case .routines:
            tabRouter.selectedTab = .training
        }
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
