//
//  MainTabBarPreviewScaffold.swift
//  AscendApp
//
//  Created by Codex on 4/17/26.
//

import SwiftUI

struct MainTabBarPreviewScaffold: View {
    let selectedTab: AppTab
    let status: MainTabBarView.Status?
    let statusBackground: Color?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Good Evening, Tyler")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(.white)

                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.accent)
                    .frame(height: 76)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Log Workout")
                                .font(.montserratBold(size: 16))
                                .foregroundStyle(.black)

                            Text("Manual entry, routines, imports")
                                .font(.montserratRegular(size: 14))
                                .foregroundStyle(.black.opacity(0.65))
                        }
                        .padding(.horizontal, 16)
                    }

                previewCard(title: "THIS WEEK", height: 108)
                previewCard(title: "WEEKLY GOAL", height: 84)
                previewCard(title: "ROUTINES", height: 92)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MainTabBarView(
                tabs: MainTabBarView.previewTabs,
                selectedTab: selectedTab,
                effectiveColorScheme: .dark,
                status: status,
                statusBackground: statusBackground,
                onSelect: { _ in }
            )
        }
        .preferredColorScheme(.dark)
    }

    private func previewCard(title: String, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.white.opacity(0.06))
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(16)
            }
    }
}

#Preview("Tab Bar With Offline Status") {
    MainTabBarPreviewScaffold(
        selectedTab: .home,
        status: .init(message: "You're offline", iconName: "wifi.slash"),
        statusBackground: .blue
    )
}

#Preview("Tab Bar With Settled Offline Status") {
    MainTabBarPreviewScaffold(
        selectedTab: .home,
        status: .init(message: "You're offline", iconName: "wifi.slash"),
        statusBackground: nil
    )
}

#Preview("Tab Bar With Reconnect Status") {
    MainTabBarPreviewScaffold(
        selectedTab: .leaderboard,
        status: .init(message: "You're back online", iconName: "checkmark.circle.fill"),
        statusBackground: .green
    )
}
