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
    let isEnabled: Bool
    let isLoading: Bool

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
        self.isEnabled = true
        self.isLoading = false
    }

    // Convenience initializer for actions
    init(
        icon: AppIconToken,
        title: String,
        iconColor: Color = .accent,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = isDestructive ? .red : iconColor
        self.destination = nil
        self.action = action
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.isLoading = isLoading
    }
}
