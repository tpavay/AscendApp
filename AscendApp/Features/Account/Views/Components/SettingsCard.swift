//
//  SettingsCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct SettingsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let options: [SettingsOption]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                SettingsRow(option: option)
                
                if index < options.count - 1 {
                    Divider()
                        .background(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    SettingsCard(
        options: [
            SettingsOption(icon: "person.circle", title: "Edit Profile", action: {}),
            SettingsOption(icon: "bell", title: "Notifications", action: {}),
            SettingsOption(icon: "paintbrush", title: "Appearance", action: {})
        ]
    )
    .padding()
    .themedBackground()
}
