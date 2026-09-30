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
    @State private var strava: StravaIntegrationViewModel?
    private let injectedStrava: StravaIntegrationViewModel?

    init(strava: StravaIntegrationViewModel? = nil) {
        injectedStrava = strava
    }

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 8)

                AppleHealthIntegrationCard()

                HeartRateMonitorIntegrationCard()

                if let strava, strava.status.isVisible {
                    StravaIntegrationCard(viewModel: strava)
                        .transition(.opacity)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .animation(.easeInOut(duration: 0.2), value: strava?.status.isVisible == true)
        }
        .themedBackground()
        .preferredColorScheme(effectiveColorScheme)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .trackOnce(screen: .integrations)
        .task {
            let strava = strava ?? injectedStrava ?? StravaIntegrationViewModel()
            self.strava = strava
            await strava.refresh()
        }
    }
}

#Preview("Dark Theme") {
    NavigationStack {
        IntegrationsView()
    }
    .preferredColorScheme(.dark)
    .modelContainer(for: [Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self], inMemory: true)
}
