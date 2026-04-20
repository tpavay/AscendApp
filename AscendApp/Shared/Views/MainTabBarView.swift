//
//  MainTabBarView.swift
//  AscendApp
//
//  Created by Codex on 4/14/26.
//

import SwiftUI
import UIKit

struct MainTabBarView: View {
    struct Status: Equatable {
        let message: String
        let iconName: String
    }

    let tabs: [TabItem]
    let selectedTab: AppTab
    let effectiveColorScheme: ColorScheme
    let status: Status?
    let statusBackground: Color?
    let onSelect: (TabItem) -> Void

    // Styling knobs for the compact connectivity strip.
    private static let topInset: CGFloat = 8
    private static let tabRowBottomInset: CGFloat = 8
    private static let compactBottomInset: CGFloat = 4
    private static let previewBottomStatusAreaHeight: CGFloat = 34
    private static let statusVerticalInset: CGFloat = 6
    private static let statusFontSize: CGFloat = 13
    private static let statusIconSize: CGFloat = 11
    private static let tabLabelFontSize: CGFloat = 10
    private static let tabIconSize: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabBarButton(for: tab)
            }
        }
        .padding(.top, Self.topInset)
        .padding(.bottom, Self.tabRowBottomInset + Self.compactBottomInset)
        .background {
            tabBarBackground
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                if let status {
                    statusOverlay(for: status)
                }
            }
        }
    }

    private func tabBarButton(for tab: TabItem) -> some View {
        let isSelected = selectedTab == tab.identifier

        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                let iconToUse = iconToken(for: tab, isSelected: isSelected)
                tabBarIcon(for: iconToUse)
                    .frame(width: Self.tabIconSize, height: Self.tabIconSize)

                Text(tab.title)
                    .font(.system(size: Self.tabLabelFontSize, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(
                isSelected
                    ? Color.accent
                    : effectiveColorScheme == .dark
                        ? .white.opacity(0.6)
                        : Color.gray
            )
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabBarBackground: some View {
        if effectiveColorScheme == .dark {
            Rectangle()
                .fill(.ultraThinMaterial)
        } else {
            Rectangle()
                .fill(Color(uiColor: .systemBackground))
        }
    }

    private func statusOverlay(for status: Status) -> some View {
        let bottomAreaHeight = bottomStatusAreaHeight

        return ZStack {
            if let statusBackground {
                Rectangle()
                    .fill(statusBackground)
            }

            HStack(spacing: 6) {
                Image(systemName: status.iconName)
                    .font(.system(size: Self.statusIconSize, weight: .semibold))

                Text(status.message)
                    .font(.system(size: Self.statusFontSize, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Self.statusVerticalInset)
        }
        .frame(maxWidth: .infinity, minHeight: bottomAreaHeight, maxHeight: bottomAreaHeight)
        .offset(y: bottomAreaHeight)
        .allowsHitTesting(false)
    }

    private var bottomStatusAreaHeight: CGFloat {
        let windowInset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0

        return max(windowInset, Self.previewBottomStatusAreaHeight)
    }

    private func iconToken(for tab: TabItem, isSelected: Bool) -> AppIconToken {
        if isSelected, let selectedIcon = tab.selectedIcon {
            return selectedIcon
        }
        return tab.icon
    }

    @ViewBuilder
    private func tabBarIcon(for token: AppIconToken) -> some View {
        switch token.source {
        case .asset(let name):
            Image(uiImage: resizedTabBarImage(named: name))
        case .systemSymbol:
            AppIcon(token: token, pointSize: 20)
        }
    }

    private func resizedTabBarImage(named name: String) -> UIImage {
        let size = CGSize(width: Self.tabIconSize, height: Self.tabIconSize)
        guard let sourceImage = UIImage(named: name) else {
            return UIImage(systemName: "questionmark.circle") ?? UIImage()
        }

        let format = UIGraphicsImageRendererFormat.default()
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let rendered = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: size))
        }

        return rendered.withRenderingMode(.alwaysTemplate)
    }
}

#if DEBUG
extension MainTabBarView {
    @MainActor
    static var previewTabs: [TabItem] {
        [
            TabItem(identifier: .home, title: "Home", icon: .tabHome, selectedIcon: .tabHomeSelected) { Color.clear },
            TabItem(identifier: .workouts, title: "Workouts", icon: .tabWorkouts, selectedIcon: .tabWorkoutsSelected) { Color.clear },
            TabItem(identifier: .progress, title: "Progress", icon: .tabProgress, selectedIcon: .tabProgressSelected) { Color.clear },
            TabItem(identifier: .leaderboard, title: "Leaderboard", icon: .tabLeaderboard, selectedIcon: .tabLeaderboardSelected) { Color.clear },
            TabItem(identifier: .settings, title: "Settings", icon: .tabSettings, selectedIcon: .tabSettingsSelected) { Color.clear }
        ]
    }
}

#Preview("Default Tab Bar") {
    VStack(spacing: 0) {
        Spacer()
        MainTabBarView(
            tabs: MainTabBarView.previewTabs,
            selectedTab: .home,
            effectiveColorScheme: .dark,
            status: nil,
            statusBackground: nil,
            onSelect: { _ in }
        )
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Offline Highlight") {
    VStack(spacing: 0) {
        Spacer()
        MainTabBarView(
            tabs: MainTabBarView.previewTabs,
            selectedTab: .home,
            effectiveColorScheme: .dark,
            status: .init(message: "You're offline", iconName: "wifi.slash"),
            statusBackground: .blue,
            onSelect: { _ in }
        )
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Offline Settled") {
    VStack(spacing: 0) {
        Spacer()
        MainTabBarView(
            tabs: MainTabBarView.previewTabs,
            selectedTab: .home,
            effectiveColorScheme: .dark,
            status: .init(message: "You're offline", iconName: "wifi.slash"),
            statusBackground: nil,
            onSelect: { _ in }
        )
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Back Online") {
    VStack(spacing: 0) {
        Spacer()
        MainTabBarView(
            tabs: MainTabBarView.previewTabs,
            selectedTab: .leaderboard,
            effectiveColorScheme: .dark,
            status: .init(message: "You're back online", iconName: "checkmark.circle.fill"),
            statusBackground: .green,
            onSelect: { _ in }
        )
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
#endif
