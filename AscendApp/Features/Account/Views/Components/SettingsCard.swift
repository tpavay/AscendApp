//
//  SettingsCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct SettingsCard: View {
    let options: [SettingsOption]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                SettingsRow(option: option)
                
                if index < options.count - 1 {
                    Divider()
                        .background(.white.opacity(0.1))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.jetLighter.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

#Preview {
    SettingsCard(
        options: [
            SettingsOption(icon: .settingsEditProfile, title: "Edit Profile", action: {}),
            SettingsOption(icon: .settingsNotifications, title: "Notifications", action: {}),
            SettingsOption(icon: .settingsIntegrations, title: "Integrations", action: {})
        ]
    )
    .padding()
    .themedBackground()
}
