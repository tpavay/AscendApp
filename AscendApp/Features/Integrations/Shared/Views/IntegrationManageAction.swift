//
//  IntegrationManageAction.swift
//  AscendApp
//
//  Created by Codex on 3/12/26.
//

import SwiftUI

struct IntegrationManageAction: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let subtitle: String?
    let iconTint: Color
    let tone: AppSheetCardTone
    let badgeCount: Int
    let isEnabled: Bool
    let action: () -> Void

    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        iconTint: Color,
        tone: AppSheetCardTone = .standard,
        badgeCount: Int = 0,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.iconTint = iconTint
        self.tone = tone
        self.badgeCount = badgeCount
        self.isEnabled = isEnabled
        self.action = action
    }
}
