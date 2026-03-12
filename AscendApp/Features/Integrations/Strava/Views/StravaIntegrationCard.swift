//
//  StravaIntegrationCard.swift
//  AscendApp
//
//  Created by Claude Code on 12/9/24.
//

import SwiftUI

struct StravaIntegrationCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var stravaManager = StravaManager.shared
    @State private var showingDisconnectConfirmation = false

    // Strava brand color
    private let stravaOrange = Color(red: 252/255, green: 76/255, blue: 2/255)

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        let style = IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme)

        IntegrationCardShell(style: style) {
            IntegrationCardHeader(
                assetImage: "strava-icon",
                title: "Strava",
                titleColor: style.primaryText
            ) {
                headerAction
            }

            if !stravaManager.isConnected && !stravaManager.isConnecting {
                Text("Connect your Strava account to share your workouts with your Strava community.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(style.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = stravaManager.connectionError {
                Text(error)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if stravaManager.isConnected {
                Divider()
                    .background(style.divider)

                Toggle(isOn: Binding(
                    get: { stravaManager.autoSyncEnabled },
                    set: { stravaManager.autoSyncEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-sync workouts")
                            .font(.montserratMedium(size: 15))
                            .foregroundStyle(style.primaryText)

                        Text("Automatically push new workouts to Strava")
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(style.tertiaryText)
                    }
                }
                .tint(stravaOrange)
            }
        }
        .confirmationDialog(
            "Disconnect from Strava?",
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    try? await stravaManager.disconnect()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Strava connection will be removed. You can reconnect at any time.")
        }
    }

    @ViewBuilder
    private var headerAction: some View {
        if stravaManager.isConnected {
            IntegrationCardActionButton("Disconnect", color: .red) {
                showingDisconnectConfirmation = true
            }
        } else {
            IntegrationCardActionButton(
                "Connect",
                color: stravaOrange,
                isLoading: stravaManager.isConnecting
            ) {
                connectToStrava()
            }
        }
    }

    // MARK: - Actions

    private func connectToStrava() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }

        Task { @MainActor in
            await stravaManager.startOAuthFlow(presentationAnchor: window)
        }
    }
}

#Preview("Disconnected - Light") {
    StravaIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.light)
}

#Preview("Disconnected - Dark") {
    StravaIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.dark)
}
