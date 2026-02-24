//
//  AppleHealthIntegrationCard.swift
//  AscendApp
//
//  Created by Claude Code on 1/3/26.
//

import SwiftUI
import HealthKit

struct AppleHealthIntegrationCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var healthKitService = HealthKitService.shared

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Main row: Icon | Apple Health | Manage
            HStack(spacing: 12) {
                // Apple Health icon
                Image("appleHealth-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 8))

                Text("Apple Health")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                // Manage button - opens Health app
                if !healthKitService.isHealthDataAvailable {
                    Text("Not Available")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(.gray)
                } else {
                    Button("Manage") {
                        openHealthApp()
                    }
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.accent)
                }
            }

            // Instructions for managing permissions
            if healthKitService.isHealthDataAvailable {
                Text("Tap Manage, then: Profile → Apps → Ascend")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Apple Health is not available on this device.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Actions

    private func openHealthApp() {
        // Open the Health app - users can manage permissions from:
        // Health app → Profile (top right) → Apps → Ascend
        if let healthURL = URL(string: "x-apple-health://") {
            UIApplication.shared.open(healthURL)
        }
    }
}

#Preview("Light Theme") {
    AppleHealthIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.light)
}

#Preview("Dark Theme") {
    AppleHealthIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.dark)
}
