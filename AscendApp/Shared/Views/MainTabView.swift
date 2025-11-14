//
//  MainTabView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import SwiftUI

struct MainTabView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @StateObject private var tabRouter = TabRouter()
    
    // Easy configuration - just change this array to modify tabs
    private let tabs = TabItem.activeTabs
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }
    
    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            ForEach(tabs) { tab in
                tab.view
                    .tabItem {
                        let isSelected = tabRouter.selectedTab == tab.identifier
                        let iconToUse = getIconName(for: tab, isSelected: isSelected)
                        
                        if tab.iconName.starts(with: "Home") || tab.iconName.starts(with: "Settings") {
                            Image(iconToUse)
                                .renderingMode(.template)
                        } else {
                            Image(systemName: iconToUse)
                        }
                        Text(tab.title)
                    }
                    .tag(tab.identifier)
            }
        }
        .accentColor(.accent)
        .environmentObject(tabRouter)
        .onAppear {
            setupTabBarAppearance()
        }
        .onChange(of: effectiveColorScheme) { _, _ in
            setupTabBarAppearance()
        }
        .themeAware()
    }
    
    private func getIconName(for tab: TabItem, isSelected: Bool) -> String {
        if isSelected, let selectedIcon = tab.selectedIconName {
            return selectedIcon
        }
        return tab.iconName
    }
    
    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        
        if effectiveColorScheme == .dark {
            // Dark mode styling - transparent to show gradient behind
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            
            // Add subtle blur effect that works with gradient
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            
            // Normal state
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.6)
            ]
            
            // Selected state - using accent color
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.accent)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(Color.accent)
            ]
        } else {
            // Light mode styling - clean white background
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBackground
            appearance.shadowColor = UIColor.systemGray4
            
            // Normal state
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.systemGray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.systemGray
            ]
            
            // Selected state - using accent color
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.accent)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(Color.accent)
            ]
        }
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    MainTabView()
        .environment(AuthenticationViewModel())
}
