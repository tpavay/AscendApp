//
//  DebugAction.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftUI

struct DebugAction: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let iconColor: Color
    let isDestructive: Bool

    init(
        title: String,
        description: String,
        icon: String = "wrench.and.screwdriver",
        iconColor: Color = .accent,
        isDestructive: Bool = false
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.iconColor = iconColor
        self.isDestructive = isDestructive
    }
}

struct DebugSection: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let actions: [DebugAction]

    init(title: String, subtitle: String? = nil, actions: [DebugAction]) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions
    }
}
