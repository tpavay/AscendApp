//
//  AppleHealthManageSheet.swift
//  AscendApp
//
//  Created by Codex on 4/20/26.
//

import SwiftUI

struct AppleHealthManageSheet: View {
    @Binding var isPresented: Bool
    @Binding var autoImportEnabled: Bool

    let attentionCount: Int
    let onSyncNow: () -> Void
    let onReviewImports: () -> Void
    let onOpenHealthPermissions: () -> Void

    private var autoImportSubtitle: String {
        "Automatically import new Apple Health workouts and keep their follow-up review ready in Ascend."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IntegrationManageHeader(assetImage: "appleHealth-icon", title: "Apple Health")

            IntegrationManageToggleCard(
                title: "Auto-import new workouts",
                subtitle: autoImportSubtitle,
                isOn: $autoImportEnabled,
                isEnabled: true
            )

            manageActionButton(
                systemImage: "arrow.clockwise",
                title: "Sync now",
                badgeCount: 0,
                action: onSyncNow
            )

            manageActionButton(
                systemImage: "sparkles",
                title: "Review workouts",
                badgeCount: attentionCount,
                action: onReviewImports
            )

            manageActionButton(
                systemImage: "heart.text.square",
                title: "Manage Health permissions",
                badgeCount: 0,
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
        badgeCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            IntegrationManageActionRow(
                action: IntegrationManageAction(
                    systemImage: systemImage,
                    title: title,
                    iconTint: .accent,
                    badgeCount: badgeCount,
                    isEnabled: true,
                    action: action
                )
            )
        }
        .buttonStyle(.plain)
    }
}
