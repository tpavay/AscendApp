//
//  SettingsRow.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct SettingsRow: View {
    let option: SettingsOption
    
    var body: some View {
        Group {
            if let destination = option.destination {
                NavigationLink(destination: destination) {
                    rowContent
                }
            } else if let action = option.action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
                .disabled(!option.isEnabled)
            } else {
                rowContent
            }
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: 16) {
            // Icon
            AppIcon(token: option.icon, pointSize: 20, weight: .medium)
                .foregroundStyle(option.iconColor)
                .frame(width: 24, height: 24)
            
            // Title
            Text(option.title)
                .font(.montserratMedium)
                .foregroundStyle(option.isDestructive ? .red : .white)
            
            Spacer()
            
            if option.isLoading {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Restoring purchases")
            } else {
                AppIcon(token: .disclosureChevronRight, pointSize: 14, weight: .medium)
                    .foregroundStyle(option.isDestructive ? .red.opacity(0.6) : .white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .opacity(option.isEnabled ? 1 : 0.6)
    }
}

#Preview {
    VStack {
        SettingsRow(
            option: SettingsOption(
                icon: .settingsEditProfile,
                title: "Edit Profile",
                action: {}
            )
        )
        
        SettingsRow(
            option: SettingsOption(
                icon: .settingsIntegrations,
                title: "Integrations",
                destination: AnyView(Text("Integrations View"))
            )
        )
    }
    .themedBackground()
}
