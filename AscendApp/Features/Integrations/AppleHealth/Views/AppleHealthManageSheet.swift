//
//  AppleHealthManageSheet.swift
//  AscendApp
//
//  Created by Codex on 4/20/26.
//

import SwiftUI

struct AppleHealthManageSheet: View {
    @Binding var isPresented: Bool

    let onCheckNow: () -> Void
    let onOpenHealthPermissions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IntegrationManageHeader(assetImage: "appleHealth-icon", title: "Apple Health")

            manageActionButton(
                systemImage: "arrow.clockwise",
                title: "Check for heart rate now",
                action: onCheckNow
            )

            manageActionButton(
                systemImage: "heart.text.square",
                title: "Manage Health permissions",
                action: onOpenHealthPermissions
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

    private func manageActionButton(
        systemImage: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            IntegrationManageActionRow(
                action: IntegrationManageAction(
                    systemImage: systemImage,
                    title: title,
                    iconTint: .accent,
                    badgeCount: 0,
                    isEnabled: true,
                    action: action
                )
            )
        }
        .buttonStyle(.plain)
    }
}
