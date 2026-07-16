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
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    private let homeDashboard: HomeDashboardViewModel
    @State private var showingImportSheet = false
    @State private var showingStartActionSheet = false
    @State private var showingClimbBrowse = false
    @State private var showingJustClimbSetup = false
    @State private var showingManualWorkoutForm = false
    @State private var showingCompletedWorkoutShare = false
    @State private var pendingStartAction: HomeStartAction?
    @State private var selectedHomeClimb: Climb?
    @State private var activeJustClimbGoal: JustClimbGoal?
    @State private var completedWorkout: Workout?
    @State private var globeViewModel = GlobeViewModel()
    @AppStorage("firstLaunchDate") private var firstLaunchDate: Double = 0
    @State private var autoImportedReviewWorkout: Workout?

    private var isHomeTabSelected: Bool {
        tabRouter.selectedTab == .home
    }

    init(
        homeDashboard: HomeDashboardViewModel = HomeDashboardViewModel(),
        tabRouter: TabRouter
    ) {
        self.homeDashboard = homeDashboard
        self.tabRouter = tabRouter
    }

    private var hasBlockingModalPresentation: Bool {
        showingImportSheet ||
        showingStartActionSheet ||
        showingJustClimbSetup ||
        showingManualWorkoutForm ||
        showingCompletedWorkoutShare
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
                importBell
                .onChange(of: importCoordinator.attentionCount) { oldValue, newValue in
                    debugLog("🔄 HomeView detected count change from \(oldValue) to \(newValue)")
                    syncAutoImportedReviewPresentation()
                }
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
        .sheet(isPresented: $showingImportSheet) {
            WorkoutImportSheet()
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
        .sheet(isPresented: $showingManualWorkoutForm) {
            WorkoutFormView(
                showingWorkoutForm: $showingManualWorkoutForm,
                onWorkoutCompleted: handleManualWorkoutCompleted
            )
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showingCompletedWorkoutShare) {
            if let completedWorkout {
                ShareComposerView(workout: completedWorkout)
            }
        }
        .sheet(item: $autoImportedReviewWorkout, onDismiss: {
            importCoordinator.dismissCurrentAutoImportedReview()
        }) { workout in
            AutoImportedWorkoutReviewView(
                workout: workout,
                onDone: {
                    importCoordinator.completeAutoImportedReview(for: workout.id)
                    autoImportedReviewWorkout = nil
                },
                onDelete: {
                    importCoordinator.completeAutoImportedReview(for: workout.id)
                    autoImportedReviewWorkout = nil
                }
            )
            .appSheetStyle(.detents([.fraction(0.75), .large]), isInteractiveDismissDisabled: true)
        }
        .task {
            // Set first launch date if not already set
            if firstLaunchDate == 0 {
                firstLaunchDate = Date().timeIntervalSince1970
            }

            // Configure the unified import service with model context
            importCoordinator.configure(modelContext: modelContext)
            globeViewModel.loadIfNeeded(modelContext: modelContext)
            refreshHomeDashboard(forceRank: true)
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()

            // Check for workouts from all sources on app launch
            await importCoordinator.refreshPendingImports(trigger: .homeEntry)
            syncAutoImportedReviewPresentation()
        }
        .onChange(of: tabRouter.selectedTab) { _, newValue in
            guard newValue == .home else { return }
            refreshHomeDashboard()
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()
            Task {
                await importCoordinator.refreshPendingImports(trigger: .homeEntry)
                syncAutoImportedReviewPresentation()
            }
        }
        .onChange(of: importCoordinator.currentAutoImportedReviewWorkoutID) { _, _ in
            syncAutoImportedReviewPresentation()
        }
        .onChange(of: showingImportSheet) { _, isShowing in
            guard !isShowing else { return }
            syncAutoImportedReviewPresentation()
        }
        .onChange(of: authVM.user?.uid) { _, _ in
            refreshHomeDashboard(forceRank: true)
            refreshTodayClimbStake()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutsDidChange)) { _ in
            refreshHomeDashboard(forceRank: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check for new workouts when app comes to foreground (throttled to prevent spam)
            refreshHomeDashboard(forceRank: true)
            refreshLiveClimbCommunityStats()
            refreshTodayClimbStake()
            Task {
                await importCoordinator.refreshPendingImports(trigger: .automatic)
                syncAutoImportedReviewPresentation()
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            // Reset throttling when app goes to background so next foreground check works
            importCoordinator.resetAutomaticCheckThrottle()
        }
    }

    private var importBell: some View {
        NotificationBellView(pendingImports: importCoordinator.attentionCount) {
            openImportInbox()
        }
        .frame(width: 44, height: 44)
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
        case .manualWorkout:
            showingManualWorkoutForm = true
        }
    }

    private func handleManualWorkoutCompleted(_ workout: Workout) {
        completedWorkout = workout
        showingManualWorkoutForm = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showingCompletedWorkoutShare = true
        }
    }

    private func openImportInbox() {
        Task {
            _ = await importCoordinator.prepareImportInbox()
            showingImportSheet = true
        }
    }

    private func syncAutoImportedReviewPresentation() {
        guard isHomeTabSelected else { return }
        guard !hasBlockingModalPresentation else { return }

        if importCoordinator.presentPendingAutoImportedReviewOnHomeIfNeeded() {
            autoImportedReviewWorkout = resolveWorkout(id: importCoordinator.currentAutoImportedReviewWorkoutID)
            if autoImportedReviewWorkout == nil {
                importCoordinator.dismissCurrentAutoImportedReview()
            }
            return
        }

        if importCoordinator.currentAutoImportedReviewWorkoutID == nil {
            autoImportedReviewWorkout = nil
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

    private func resolveWorkout(id: UUID?) -> Workout? {
        guard let id else { return nil }
        let workoutID = id
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.id == workoutID
            }
        )

        return try? modelContext.fetch(descriptor).first
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
