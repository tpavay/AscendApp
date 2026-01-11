//
//  IntegrationsView.swift
//  AscendApp
//
//  Created by Claude Code on 12/9/24.
//

import SwiftUI

struct IntegrationsView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 8)

                // Strava Integration
                if FeatureFlags.isStravaEnabled {
                    StravaIntegrationCard()
                }

                // Hevy Integration
                HevyIntegrationCard()

                // Apple Health Integration
                AppleHealthIntegrationCard()

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .themedBackground()
        .preferredColorScheme(effectiveColorScheme)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

#Preview("Light Theme") {
    NavigationStack {
        IntegrationsView()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Theme") {
    NavigationStack {
        IntegrationsView()
    }
    .preferredColorScheme(.dark)
}
