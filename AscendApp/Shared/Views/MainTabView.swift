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
    @State private var themeManager = ThemeManager.shared
    @State private var tabRouter = TabRouter()
    @State private var hasCheckedRatingOnLaunch = false
    @State private var showBackOnlineBanner = false
    @State private var onlineBannerTask: Task<Void, Never>?
    @State private var showOfflineHighlight = false
    @State private var offlineHighlightTask: Task<Void, Never>?

    // Easy configuration - just change this array to modify tabs
    private let tabs = TabItem.activeTabs

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
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
        .accentColor(.accent)
        .environment(tabRouter)
        .onAppear {
            checkForRatingPromptOnLaunch()
        }
        .task {
            rebuildBestEffortCacheIfNeeded()
        }
        .onChange(of: connectivityService.isConnected) { oldValue, newValue in
            handleConnectivityChange(from: oldValue, to: newValue)
        }
        .themeAware()
        .animation(.smooth(duration: 0.2), value: connectivityService.isConnected)
        .animation(.smooth(duration: 0.2), value: showBackOnlineBanner)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack {
                HomeView()
            }
            .id("HomeNavigationStack")
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
                ProfileView()
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

    private func checkForRatingPromptOnLaunch() {
        // Only check once per app session
        guard !hasCheckedRatingOnLaunch else { return }
        hasCheckedRatingOnLaunch = true

        // Check if user is eligible for rating prompt based on workout count
        // This handles cases where user imported workouts and became eligible
        // Note: We fetch count on-demand rather than using @Query to avoid crashes
        // when workouts are deleted (e.g., during account deletion) while this view is in the hierarchy
        let workoutCount = (try? modelContext.fetchCount(FetchDescriptor<Workout>())) ?? 0
        AppStoreRatingManager.shared.checkAndRequestReviewIfNeeded(currentWorkoutCount: workoutCount)
    }

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
