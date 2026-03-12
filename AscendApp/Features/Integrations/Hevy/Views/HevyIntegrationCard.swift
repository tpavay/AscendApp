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
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var showingApiKeyEntry = false
    @State private var showingManageSheet = false
    @State private var showingDisconnectConfirmationSheet = false
    @State private var shouldPresentDisconnectConfirmationAfterManageDismiss = false

    var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    private var canAutoLinkAppleHealth: Bool {
        importCoordinator.appleHealthConnectionState == .connected
    }

    private var hevyStatusLabel: String? {
        hevyManager.isConnected ? "Connected" : nil
    }

    private var hevyDescription: String {
        "Import your stairstepper workouts from the Hevy app."
    }

    var body: some View {
        let style = IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme)

        IntegrationCardShell(style: style) {
            IntegrationCardHeader(
                assetImage: "hevy-icon",
                title: "Hevy",
                subtitle: hevyStatusLabel,
                titleColor: style.primaryText,
                subtitleColor: .accent
            ) {
                headerAction
            }

            IntegrationCardDescriptionSection(
                style: style,
                text: hevyDescription
            )

            if let error = hevyManager.connectionError {
                Text(error.localizedDescription)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showingApiKeyEntry) {
            HevyApiKeyEntryView(onSuccess: {
                showingApiKeyEntry = false
            })
        }
        .sheet(isPresented: $showingManageSheet, onDismiss: presentDisconnectConfirmationAfterManageDismissal) {
            HevyManageSheet(
                isPresented: $showingManageSheet,
                autoLinkAppleHealth: Binding(
                    get: { canAutoLinkAppleHealth ? hevyManager.autoLinkAppleHealth : false },
                    set: { newValue in
                        guard canAutoLinkAppleHealth else { return }
                        hevyManager.autoLinkAppleHealth = newValue
                    }
                ),
                canAutoLinkAppleHealth: canAutoLinkAppleHealth,
                onDisconnect: queueDisconnectConfirmationFromManageSheet
            )
        }
        .sheet(isPresented: $showingDisconnectConfirmationSheet) {
            ConfirmationView(
                title: "Disconnect Hevy?",
                message: "Your Hevy connection will be removed. Previously imported workouts will remain.",
                confirmButtonText: "Disconnect",
                isDestructive: true,
                onCancel: {
                    showingDisconnectConfirmationSheet = false
                },
                onConfirm: {
                    hevyManager.disconnect()
                    showingDisconnectConfirmationSheet = false
                }
            )
            .appSheetStyle(.destructiveConfirmation)
        }
    }

    @ViewBuilder
    private var headerAction: some View {
        if hevyManager.isConnected {
            IntegrationCardActionButton(
                "Manage",
                appearance: .outlined(
                    foreground: IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme).subtleActionText,
                    border: IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme).subtleActionBorder
                )
            ) {
                showingManageSheet = true
            }
        } else {
            IntegrationCardActionButton(
                "Connect",
                appearance: .filled(background: .accent, foreground: .black),
                isLoading: hevyManager.isConnecting
            ) {
                showingApiKeyEntry = true
            }
        }
    }

    private func queueDisconnectConfirmationFromManageSheet() {
        shouldPresentDisconnectConfirmationAfterManageDismiss = true
        showingManageSheet = false
    }

    private func presentDisconnectConfirmationAfterManageDismissal() {
        guard shouldPresentDisconnectConfirmationAfterManageDismiss else { return }
        shouldPresentDisconnectConfirmationAfterManageDismiss = false
        showingDisconnectConfirmationSheet = true
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
