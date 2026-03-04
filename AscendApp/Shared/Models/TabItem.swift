//
//  TabItem.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

enum AppTab: Hashable {
    case home
    case workouts
    case progress
    case leaderboard
    case settings
}

@Observable
final class TabRouter {
    var selectedTab: AppTab = .home
}

struct TabItem: Identifiable, Hashable {
    let identifier: AppTab
    let title: String
    let icon: AppIconToken
    let selectedIcon: AppIconToken?
    let view: AnyView
    
    var id: AppTab { identifier }
    
    init<V: View>(identifier: AppTab, title: String, icon: AppIconToken, selectedIcon: AppIconToken? = nil, @ViewBuilder view: () -> V) {
        self.identifier = identifier
        self.title = title
        self.icon = icon
        self.selectedIcon = selectedIcon
        self.view = AnyView(view())
    }
    
    // Hashable conformance
    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.identifier == rhs.identifier
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

// MARK: - Tab Configuration
extension TabItem {
    @MainActor
    static var availableTabs: [TabItem] {
        [
            TabItem(
                identifier: .home,
                title: "Home",
                icon: .tabHome,
                selectedIcon: .tabHomeSelected
            ) {
                NavigationStack {
                    HomeView()
                }
                .id("HomeNavigationStack")
            },

            TabItem(
                identifier: .workouts,
                title: "Workouts",
                icon: .tabWorkouts,
                selectedIcon: .tabWorkoutsSelected
            ) {
                NavigationStack {
                    WorkoutListView()
                }
                .id("WorkoutsNavigationStack")
            },

            TabItem(
                identifier: .progress,
                title: "Progress",
                icon: .tabProgress,
                selectedIcon: .tabProgressSelected
            ) {
                NavigationStack {
                    ProgressTabView()
                }
                .id("ProgressNavigationStack")
            },

            TabItem(
                identifier: .leaderboard,
                title: "Leaderboard",
                icon: .tabLeaderboard,
                selectedIcon: .tabLeaderboardSelected
            ) {
                NavigationStack {
                    LeaderboardHubView()
                }
                .id("LeaderboardNavigationStack")
            },

            TabItem(
                identifier: .settings,
                title: "Settings",
                icon: .tabSettings,
                selectedIcon: .tabSettingsSelected
            ) {
                NavigationStack {
                    AccountView()
                }
                .id("SettingsNavigationStack")
            }
        ]
    }

    // Currently active tabs - easily configurable
    @MainActor
    static var activeTabs: [TabItem] {
        [
            availableTabs[0], // Home
            availableTabs[1], // Workouts
            availableTabs[2], // Progress
            availableTabs[3], // Leaderboard
            availableTabs[4]  // Settings
        ]
    }
}

// MARK: - Placeholder Views for Future Tabs
struct WorkoutPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            AppIcon(token: .tabWorkouts, pointSize: 60)
                .foregroundStyle(.accent)
            
            Text("Workouts")
                .font(.montserratBold(size: 28))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            Text("Your workout tracking will appear here")
                .font(.montserratRegular(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .themedBackground()
        .navigationTitle("Workouts")
    }
}

struct ProgressPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            AppIcon(token: .tabProgress, pointSize: 60)
                .foregroundStyle(.accent)
            
            Text("Progress")
                .font(.montserratBold(size: 28))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            Text("Your progress analytics will appear here")
                .font(.montserratRegular(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .themedBackground()
        .navigationTitle("Progress")
    }
}
