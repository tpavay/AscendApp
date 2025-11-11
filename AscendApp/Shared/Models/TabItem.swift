//
//  TabItem.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct TabItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let iconName: String
    let selectedIconName: String?
    let view: AnyView
    
    init<V: View>(title: String, iconName: String, selectedIconName: String? = nil, @ViewBuilder view: () -> V) {
        self.title = title
        self.iconName = iconName
        self.selectedIconName = selectedIconName
        self.view = AnyView(view())
    }
    
    // Hashable conformance
    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Tab Configuration
extension TabItem {
    @MainActor
    static var availableTabs: [TabItem] {
        [
            TabItem(
                title: "Home",
                iconName: "Home",
                selectedIconName: "HomeFill"
            ) {
                NavigationStack {
                    HomeView()
                }
                .id("HomeNavigationStack")
            },

            TabItem(
                title: "Workouts",
                iconName: "figure.stair.stepper",
                selectedIconName: "figure.stair.stepper"
            ) {
                NavigationStack {
                    WorkoutListView()
                }
                .id("WorkoutsNavigationStack")
            },

            TabItem(
                title: "Leaderboard",
                iconName: "chart.bar.fill",
                selectedIconName: "chart.bar.fill"
            ) {
                NavigationStack {
                    LeaderboardView()
                }
                .id("LeaderboardNavigationStack")
            },

            TabItem(
                title: "Progress",
                iconName: "chart.line.uptrend.xyaxis",
                selectedIconName: "chart.line.uptrend.xyaxis"
            ) {
                NavigationStack {
                    ProgressPlaceholderView()
                }
                .id("ProgressNavigationStack")
            },

            TabItem(
                title: "Settings",
                iconName: "Settings",
                selectedIconName: "SettingsFill"
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
            availableTabs[2], // Leaderboard
            availableTabs[4]  // Settings
        ]
    }
}

// MARK: - Placeholder Views for Future Tabs
struct WorkoutPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.stair.stepper")
                .font(.system(size: 60, weight: .light))
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
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60, weight: .light))
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
