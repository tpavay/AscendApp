//
//  AppleHealthIntegrationCard.swift
//  AscendApp
//
//  Created by Claude Code on 1/3/26.
//

import SwiftUI
import SwiftData
import UIKit

struct AppleHealthIntegrationCard: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var enrichmentService = AppleHealthEnrichmentService.shared
    @State private var showingManageSheet = false
    @State private var actionTask: Task<Void, Never>?
    @State private var isConnecting = false
    @State private var alertMessage = ""
    @State private var showingErrorAlert = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    private var connectionState: AppleHealthConnectionState {
        enrichmentService.appleHealthConnectionState
    }

    var body: some View {
        let style = IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme)

        IntegrationCardShell(style: style) {
            IntegrationCardHeader(
                assetImage: "appleHealth-icon",
                title: "Apple Health",
                subtitle: headerStatusLabel,
                titleColor: style.primaryText,
                subtitleColor: statusColor
            ) {
                headerAction
            }

            IntegrationCardDescriptionSection(
                style: style,
                text: statusMessage
            )
        }
        .sheet(isPresented: $showingManageSheet) {
            AppleHealthManageSheet(
                isPresented: $showingManageSheet,
                onCheckNow: checkForHeartRateFromManageSheet,
                onOpenHealthPermissions: openPermissionsFromManageSheet
            )
        }
        .alert("Apple Health", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .task {
            enrichmentService.configure(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private var headerAction: some View {
        switch connectionState {
        case .unavailable:
            EmptyView()
        case .neverConnected:
            IntegrationCardActionButton(
                "Connect",
                appearance: .filled(background: .accent, foreground: .black),
                isLoading: isConnecting
            ) {
                connectAppleHealth()
            }
        case .connected, .revoked:
            IntegrationCardActionButton(
                "Manage",
                appearance: .outlined(
                    foreground: IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme).subtleActionText,
                    border: IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme).subtleActionBorder
                )
            ) {
                showingManageSheet = true
            }
        }
    }

    private var headerStatusLabel: String? {
        switch connectionState {
        case .unavailable, .neverConnected:
            return nil
        case .connected:
            return "Connected"
        case .revoked:
            return "Permissions Disabled"
        }
    }

    private var statusMessage: String {
        switch connectionState {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .neverConnected, .revoked:
            return "Connect Apple Health to attach heart rate and calories to the climbs you run in Ascend."
        case .connected:
            return "Heart rate and calories attach to the climbs you run in Ascend."
        }
    }

    private var statusColor: Color {
        switch connectionState {
        case .connected:
            return .accent
        case .revoked:
            return .orange
        case .unavailable, .neverConnected:
            return .secondary
        }
    }

    private func connectAppleHealth() {
        actionTask?.cancel()
        isConnecting = true
        actionTask = Task {
            let didConnect = await enrichmentService.requestAppleHealthAuthorizationIfNeeded()
            isConnecting = false

            guard didConnect else {
                if let errorMessage = enrichmentService.lastErrorMessage, !errorMessage.isEmpty {
                    presentError(errorMessage)
                }
                return
            }
        }
    }

    private func checkForHeartRateFromManageSheet() {
        showingManageSheet = false
        actionTask?.cancel()
        actionTask = Task {
            await enrichmentService.refreshPendingEnrichment(
                modelContext: modelContext,
                isUserInitiated: true
            )
            if let errorMessage = enrichmentService.lastErrorMessage, !errorMessage.isEmpty {
                presentError(errorMessage)
            }
        }
    }

    private func openPermissionsFromManageSheet() {
        showingManageSheet = false
        openHealthApp()
    }

    private func openHealthApp() {
        guard let healthURL = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(healthURL)
    }

    private func presentError(_ message: String) {
        alertMessage = message
        showingErrorAlert = true
    }
}

#Preview("Dark Theme") {
    AppleHealthIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.dark)
        .modelContainer(for: [Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self], inMemory: true)
}
