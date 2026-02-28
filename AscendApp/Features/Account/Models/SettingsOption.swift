//
//  SettingsOption.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftUI

struct SettingsOption: Identifiable {
    let id = UUID()
    let icon: AppIconToken
    let title: String
    let iconColor: Color
    let destination: AnyView?
    let action: (() -> Void)?
    let isDestructive: Bool

    // Private initializer
    private init(
        icon: AppIconToken,
        title: String,
        iconColor: Color,
        destination: AnyView?,
        action: (() -> Void)?,
        isDestructive: Bool
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.destination = destination
        self.action = action
        self.isDestructive = isDestructive
    }

    // Convenience initializer for navigation
    init<Destination: View>(
        icon: AppIconToken,
        title: String,
        iconColor: Color = .accent,
        isDestructive: Bool = false,
        destination: Destination
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = isDestructive ? .red : iconColor
        self.destination = AnyView(destination)
        self.action = nil
        self.isDestructive = isDestructive
    }

    // Convenience initializer for actions
    init(
        icon: AppIconToken,
        title: String,
        iconColor: Color = .accent,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = isDestructive ? .red : iconColor
        self.destination = nil
        self.action = action
        self.isDestructive = isDestructive
    }
}
