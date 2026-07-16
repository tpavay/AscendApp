//
//  TabItem.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

enum AppTab: Hashable {
    case home
    case training
    case leaderboard
    case profile
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
                identifier: .training,
                title: "Training",
                icon: .tabWorkouts,
                selectedIcon: .tabWorkoutsSelected
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
