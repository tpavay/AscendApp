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
        VStack(spacing: 16) {
            // Main row: Icon | Strava | Connect/Disconnect
            HStack(spacing: 12) {
                // Strava icon
                Image("strava-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 8))

                Text("Strava")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                // Connect/Disconnect button
                if stravaManager.isConnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if stravaManager.isConnected {
                    Button("Disconnect") {
                        showingDisconnectConfirmation = true
                    }
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.red)
                } else {
                    Button("Connect") {
                        connectToStrava()
                    }
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(stravaOrange)
                }
            }

            // Description (when not connected)
            if !stravaManager.isConnected && !stravaManager.isConnecting {
                Text("Connect your Strava account to share your workouts with your Strava community.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Error message
            if let error = stravaManager.connectionError {
                Text(error)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Auto-sync section (when connected)
            if stravaManager.isConnected {
                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))

                Toggle(isOn: Binding(
                    get: { stravaManager.autoSyncEnabled },
                    set: { stravaManager.autoSyncEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-sync workouts")
                            .font(.montserratMedium(size: 15))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        Text("Automatically push new workouts to Strava")
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                }
                .tint(stravaOrange)
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
