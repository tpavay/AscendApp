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

/// Why the app is showing the tab it is showing. A tab root that reports where a
/// climber came from reads this instead of inferring it from the tab alone, which
/// cannot tell a tab-bar tap apart from a card that routes to the same tab.
enum TabSelectionReason: Sendable, CaseIterable {
    case appLaunch
    case tabBarTap
    case homeRankCard
    case appRouting
}

@MainActor
@Observable
final class TabRouter {
    private var currentTab: AppTab = .home

    private(set) var selectionReason: TabSelectionReason = .appLaunch

    /// Plain assignment cannot name an entry point, so it settles on `appRouting`
    /// rather than leaving a previous entry's reason standing.
    var selectedTab: AppTab {
        get { currentTab }
        set { select(newValue, reason: .appRouting) }
    }

    func select(_ tab: AppTab, reason: TabSelectionReason) {
        selectionReason = reason
        currentTab = tab
    }
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
