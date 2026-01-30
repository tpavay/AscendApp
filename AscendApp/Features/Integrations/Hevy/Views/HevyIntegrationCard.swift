//
//  HevyIntegrationCard.swift
//  AscendApp
//
//  Created by Claude Code on 12/12/24.
//

import SwiftUI

struct HevyIntegrationCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var hevyManager = HevyManager.shared
    @State private var showingApiKeyEntry = false
    @State private var showingDisconnectConfirmation = false

    // Hevy brand color (dark purple/blue)
    private let hevyColor = Color(red: 45/255, green: 51/255, blue: 107/255)

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Main row: Icon | Hevy | Connect/Disconnect
            HStack(spacing: 12) {
                // Hevy icon
                Image("hevy-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .cornerRadius(8)

                Text("Hevy")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Spacer()

                // Connect/Disconnect button
                if hevyManager.isConnecting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if hevyManager.isConnected {
                    Button("Disconnect") {
                        showingDisconnectConfirmation = true
                    }
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.red)
                } else {
                    Button("Connect") {
                        showingApiKeyEntry = true
                    }
                    .font(.montserratMedium(size: 15))
                    .foregroundStyle(.accent)
                }
            }

            // Description (when not connected)
            if !hevyManager.isConnected && !hevyManager.isConnecting {
                Text("Import your Stair Machine workouts from Hevy. Requires Hevy Pro subscription.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Error message
            if let error = hevyManager.connectionError {
                Text(error.localizedDescription)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Connected state: show status and auto-link toggle
            if hevyManager.isConnected {
                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))

                // Connection status
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green.opacity(0.7))
                    Text("Connected")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                    Spacer()
                }

                Divider()
                    .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2))

                // Auto-link Apple Health toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { hevyManager.autoLinkAppleHealth },
                        set: { hevyManager.autoLinkAppleHealth = $0 }
                    )) {
                        Text("Auto-link Apple Health")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }
                    .tint(.accent)

                    Text("Enhance workouts with HR & calories")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
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
        .sheet(isPresented: $showingApiKeyEntry) {
            HevyApiKeyEntryView(onSuccess: {
                showingApiKeyEntry = false
            })
        }
        .confirmationDialog(
            "Disconnect from Hevy?",
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                hevyManager.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Hevy connection will be removed. Previously imported workouts will remain.")
        }
    }
}

#Preview("Disconnected - Light") {
    HevyIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.light)
}

#Preview("Disconnected - Dark") {
    HevyIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.dark)
}
