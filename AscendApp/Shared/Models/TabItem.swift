//
//  TabItem.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

enum AppTab: Hashable {
    case home
    case leaderboard
    case profile
    case workouts
    case progress
    case settings
}

@MainActor
@Observable
final class TabRouter {
    var selectedTab: AppTab = .home
}

struct TabItem: Identifiable, Hashable {
    let identifier: AppTab
    let title: String
    let icon: AppIconToken
    let selectedIcon: AppIconToken?
    
    var id: AppTab { identifier }
    
    init(identifier: AppTab, title: String, icon: AppIconToken, selectedIcon: AppIconToken? = nil) {
        self.identifier = identifier
        self.title = title
        self.icon = icon
        self.selectedIcon = selectedIcon
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
            ),

            TabItem(
                identifier: .leaderboard,
                title: "Leaderboard",
                icon: .tabLeaderboard,
                selectedIcon: .tabLeaderboardSelected
            ),

            TabItem(
                identifier: .profile,
                title: "Profile",
                icon: .tabProfile,
                selectedIcon: .tabProfileSelected
            )
        ]
    }

    // Currently active tabs - easily configurable
    @MainActor
    static var activeTabs: [TabItem] {
        availableTabs
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
