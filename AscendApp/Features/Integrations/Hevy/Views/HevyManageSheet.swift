//
//  HevyManageSheet.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct HevyManageSheet: View {
    @Binding var isPresented: Bool
    @Binding var autoLinkAppleHealth: Bool
    let canAutoLinkAppleHealth: Bool
    let onDisconnect: () -> Void

    private var toggleSubtitle: String? {
        canAutoLinkAppleHealth
            ? "Connect Apple Health to automatically sync workouts between both services."
            : "Connect Apple Health to automatically sync workouts between both services."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IntegrationManageHeader(assetImage: "hevy-icon", title: "Hevy")

            IntegrationManageToggleCard(
                title: "Auto-link Apple Health",
                subtitle: toggleSubtitle,
                isOn: $autoLinkAppleHealth,
                isEnabled: canAutoLinkAppleHealth
            )

            IntegrationManageDestructiveButton(
                title: "Disconnect Hevy",
                action: onDisconnect
            )

            Button("Close") {
                isPresented = false
            }
            .appSheetButtonStyle(tone: .subtle)
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .appSheetBackground()
        .appSheetStyle(.actionMenu)
    }
}
