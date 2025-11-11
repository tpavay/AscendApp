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
    let icon: String
    let title: String
    let iconColor: Color
    let destination: AnyView?
    let action: (() -> Void)?

    // Private initializer
    private init(
        icon: String,
        title: String,
        iconColor: Color,
        destination: AnyView?,
        action: (() -> Void)?
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.destination = destination
        self.action = action
    }

    // Convenience initializer for navigation
    init<Destination: View>(
        icon: String,
        title: String,
        iconColor: Color = .accent,
        destination: Destination
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.destination = AnyView(destination)
        self.action = nil
    }

    // Convenience initializer for actions
    init(
        icon: String,
        title: String,
        iconColor: Color = .accent,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.destination = nil
        self.action = action
    }
}
