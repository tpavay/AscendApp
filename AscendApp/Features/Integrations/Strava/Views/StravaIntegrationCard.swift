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
        VStack(spacing: 20) {
            // Header with Strava branding
            HStack(spacing: 12) {
                // Strava icon placeholder (use SF Symbol as fallback)
                ZStack {
                    Circle()
                        .fill(stravaOrange.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: "figure.stairs")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(stravaOrange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Strava")
                        .font(.montserratSemiBold(size: 18))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text("Push workouts to Strava")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                }

                Spacer()
            }

            if stravaManager.isConnected {
                connectedContent
            } else {
                disconnectedContent
            }

            // Error message
            if let error = stravaManager.connectionError {
                Text(error)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
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

    // MARK: - Connected State

    @ViewBuilder
    private var connectedContent: some View {
        VStack(spacing: 16) {
            // Connection status
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text("Connected as \(stravaManager.athleteName)")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()
            }

            Divider()
                .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))

            // Auto-sync toggle
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

            // Disconnect button
            Button(action: {
                showingDisconnectConfirmation = true
            }) {
                Text("Disconnect")
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.red)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Disconnected State

    @ViewBuilder
    private var disconnectedContent: some View {
        VStack(spacing: 16) {
            Text("Connect your Strava account to automatically share your stair climbing workouts.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)

            // Connect button
            Button(action: connectToStrava) {
                HStack(spacing: 10) {
                    if stravaManager.isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 16, weight: .semibold))
                    }

                    Text(stravaManager.isConnecting ? "Connecting..." : "Connect with Strava")
                        .font(.montserratSemiBold(size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(stravaOrange)
                )
            }
            .disabled(stravaManager.isConnecting)
            .opacity(stravaManager.isConnecting ? 0.7 : 1.0)
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
