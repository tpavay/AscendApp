//
//  MainTabView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(NetworkConnectivityService.self) private var connectivityService
    @Environment(TabRouter.self) private var tabRouter
    @State private var themeManager = ThemeManager.shared
    @State private var homeNavigationPath: [HomeNavigationDestination] = []
    @State private var homeDashboard = HomeDashboardViewModel()
    @State private var profileScreen = ProfileScreenViewModel()
    @State private var showBackOnlineBanner = false
    @State private var onlineBannerTask: Task<Void, Never>?
    @State private var showOfflineHighlight = false
    @State private var offlineHighlightTask: Task<Void, Never>?

    // Easy configuration - just change this array to modify tabs
    private let tabs = TabItem.activeTabs

    private enum HomeNavigationDestination: Hashable {
        case onboardingFirstClimb(String)
        case pushClimbDrop(String)
        case liveActivitySession(String, String?)
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        @Bindable var tabRouter = tabRouter

        TabView(selection: $tabRouter.selectedTab) {
            ForEach(tabs) { tab in
                if tab.identifier == tabRouter.selectedTab {
                    // Keep hidden tabs unmounted so inactive tab roots do not run SwiftData queries or animations.
                    tabContent(for: tab.identifier)
                        .tag(tab.identifier)
                        .tabItem {
                            Text(tab.title)
                        }
                        .toolbar(.hidden, for: .tabBar)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .tint(Color.ascendAccent)
        .accentColor(Color.ascendAccent)
        .task {
            rebuildBestEffortCacheIfNeeded()
            consumePendingFirstClimbHandoffIfNeeded()
            consumePendingPushDestinationIfNeeded()
            consumePendingLiveActivityRouteIfNeeded()
        }
        .onChange(of: connectivityService.isConnected) { oldValue, newValue in
            handleConnectivityChange(from: oldValue, to: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationDestinationDidChange)) { _ in
            consumePendingPushDestinationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .liveClimbActivityRouteDidChange)) { _ in
            consumePendingLiveActivityRouteIfNeeded()
        }
        .themeAware()
        .animation(.smooth(duration: 0.2), value: connectivityService.isConnected)
        .animation(.smooth(duration: 0.2), value: showBackOnlineBanner)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: $homeNavigationPath) {
                HomeView(homeDashboard: homeDashboard)
                    .navigationDestination(for: HomeNavigationDestination.self) { destination in
                        homeDestination(for: destination)
                    }
            }
            .id("HomeNavigationStack")
        case .training:
            NavigationStack {
                RoutinesView(presentation: .tab)
            }
            .id("TrainingNavigationStack")
        case .workouts:
            NavigationStack {
                WorkoutListView()
            }
            .id("WorkoutsNavigationStack")
        case .progress:
            NavigationStack {
                ProgressTabView()
            }
            .id("ProgressNavigationStack")
        case .leaderboard:
            NavigationStack {
                LeaderboardView()
            }
            .id("LeaderboardNavigationStack")
        case .profile:
            NavigationStack {
                ProfileView(viewModel: profileScreen)
            }
            .id("ProfileNavigationStack")
        case .settings:
            NavigationStack {
                AccountView()
            }
            .id("SettingsNavigationStack")
        }
    }

    // MARK: - Custom Tab Bar

    private var tabBar: some View {
        MainTabBarView(
            tabs: tabs,
            selectedTab: tabRouter.selectedTab,
            effectiveColorScheme: effectiveColorScheme,
            status: tabBarStatus,
            statusBackground: tabBarAccentBackground
        ) { tab in
            guard tabRouter.selectedTab != tab.identifier else { return }

            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            tabRouter.selectedTab = tab.identifier
        }
    }

    private var tabBarStatus: MainTabBarView.Status? {
        if connectivityService.isConnected == false {
            return .init(message: "You're offline", iconName: "wifi.slash")
        } else if showBackOnlineBanner {
            return .init(message: "You're back online", iconName: "checkmark.circle.fill")
        }
        return nil
    }

    private var tabBarAccentBackground: Color? {
        if showOfflineHighlight {
            return Color.blue
        } else if showBackOnlineBanner {
            return Color.green
        }
        return nil
    }

    // MARK: - Helpers

    private func rebuildBestEffortCacheIfNeeded() {
        do {
            try BestEffortCacheStore.rebuildIfNeeded(
                modelContext: modelContext,
                userId: authVM.user?.uid
            )
        } catch {
            print("Failed to rebuild Best Effort cache: \(error)")
        }
    }

    @ViewBuilder
    private func homeDestination(for destination: HomeNavigationDestination) -> some View {
        switch destination {
        case .onboardingFirstClimb(let climbId):
            climbDetailDestination(for: climbId, analyticsEntryPoint: .homeDaily, onboardingCoach: .firstClimb)
        case .pushClimbDrop(let climbId):
            climbDetailDestination(for: climbId, analyticsEntryPoint: .homeExplore, onboardingCoach: nil)
        case .liveActivitySession(let sessionID, let climbID):
            liveActivityDestination(sessionID: sessionID, climbID: climbID)
        }
    }

    @ViewBuilder
    private func climbDetailDestination(
        for climbId: String,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint,
        onboardingCoach: ClimbDetailOnboardingCoachMode?
    ) -> some View {
        if let climb = try? ClimbService.shared.climb(for: climbId) {
            ClimbDetailView(
                climb: climb,
                analyticsEntryPoint: analyticsEntryPoint,
                onboardingCoach: onboardingCoach
            )
        } else {
            Text("Climb unavailable")
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
                .themedBackground()
        }
    }

    private func consumePendingFirstClimbHandoffIfNeeded() {
        guard let userId = authVM.user?.uid else { return }
        guard homeNavigationPath.isEmpty else { return }
        guard let climbId = OnboardingFirstClimbHandoffStore().consume(for: userId) else { return }

        tabRouter.selectedTab = .home
        homeNavigationPath = [.onboardingFirstClimb(climbId)]
    }

    private func consumePendingPushDestinationIfNeeded() {
        guard let destination = PushNotificationRouter.shared.consumePendingDestination() else { return }

        switch destination {
        case .climbDetail(let climbId):
            if let climb = try? ClimbService.shared.climb(for: climbId) {
                tabRouter.selectedTab = .home
                homeNavigationPath = [.pushClimbDrop(climb.id)]
            }
        }
    }

    private func consumePendingLiveActivityRouteIfNeeded() {
        guard let route = LiveClimbActivityRouter.shared.consumePendingRoute() else { return }

        tabRouter.selectedTab = .home
        homeNavigationPath = [.liveActivitySession(route.sessionID, route.climbID)]
    }

    @ViewBuilder
    private func liveActivityDestination(sessionID: String, climbID: String?) -> some View {
        if let viewModel = LiveClimbSessionCoordinator.shared.activeViewModel(sessionID: sessionID) {
            LiveClimbSessionView(viewModel: viewModel)
        } else if let climbID,
                  climbID != "just-climb",
                  let climb = try? ClimbService.shared.climb(for: climbID) {
            ClimbDetailView(climb: climb, analyticsEntryPoint: .homeExplore)
        } else {
            Text("Live climb unavailable")
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
                .themedBackground()
        }
    }

    private func handleConnectivityChange(from oldValue: Bool, to newValue: Bool) {
        guard oldValue != newValue else { return }

        onlineBannerTask?.cancel()
        offlineHighlightTask?.cancel()

        if newValue {
            showOfflineHighlight = false
            showBackOnlineBanner = true
            onlineBannerTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                showBackOnlineBanner = false
            }
        } else {
            showBackOnlineBanner = false
            showOfflineHighlight = true
            offlineHighlightTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if connectivityService.isConnected == false {
                    showOfflineHighlight = false
                }
            }
        }
    }

}

#Preview {
    MainTabView()
        .environment(AuthenticationViewModel())
        .environment(NetworkConnectivityService.shared)
        .environment(TabRouter())
        .modelContainer(
            for: [
                Workout.self,
                WorkoutSourceLink.self,
                WorkoutParticipation.self,
                ClimbAttempt.self,
                BestEffortCacheEntry.self,
                BestEffortCacheMetadata.self,
                LeaderboardStats.self
            ],
            inMemory: true
        )
}

#Preview("Offline Connectivity Banner") {
    MainTabBarPreviewScaffold(
        selectedTab: .home,
        status: .init(message: "You're offline", iconName: "wifi.slash"),
        statusBackground: .blue
    )
}

#Preview("Back Online Connectivity Banner") {
    MainTabBarPreviewScaffold(
        selectedTab: .leaderboard,
        status: .init(message: "You're back online", iconName: "checkmark.circle.fill"),
        statusBackground: .green
    )
}
