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
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var showingManageSheet = false
    @State private var showingImportSheet = false
    @State private var shouldPresentImportsAfterManageDismiss = false
    @State private var actionTask: Task<Void, Never>?
    @State private var isConnecting = false
    @State private var alertMessage = ""
    @State private var showingErrorAlert = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    private var connectionState: AppleHealthConnectionState {
        importCoordinator.appleHealthConnectionState
    }

    private var pendingCount: Int {
        importCoordinator.appleHealthPendingCount
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
        .sheet(isPresented: $showingManageSheet, onDismiss: presentImportsAfterManageSheetDismissal) {
            IntegrationManageSheet(
                assetImage: "appleHealth-icon",
                title: "Apple Health",
                message: nil,
                actions: manageActions,
                onDismiss: {
                    showingManageSheet = false
                }
            )
        }
        .sheet(isPresented: $showingImportSheet) {
            WorkoutImportSheet()
        }
        .alert("Apple Health", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .task {
            importCoordinator.configure(modelContext: modelContext)
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

    private var reviewImportsTitle: String {
        pendingCount > 0 ? "Review Imports (\(pendingCount))" : "Review Imports"
    }

    private var headerStatusLabel: String? {
        switch connectionState {
        case .unavailable:
            return nil
        case .neverConnected:
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
        case .neverConnected:
            return "Import your stairstepper workouts from Apple Health."
        case .connected:
            return "Import your stairstepper workouts from Apple Health."
        case .revoked:
            return "Import your stairstepper workouts from Apple Health."
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

    private var manageActions: [IntegrationManageAction] {
        [
            IntegrationManageAction(
                systemImage: "arrow.clockwise",
                title: "Sync now",
                iconTint: .accent,
                isEnabled: connectionState == .connected
            ) {
                triggerManualSyncFromManageSheet()
            },
            IntegrationManageAction(
                systemImage: "magnifyingglass",
                title: "Review imports",
                iconTint: .accent,
                badgeCount: pendingCount,
                isEnabled: pendingCount > 0
            ) {
                queueImportReviewFromManageSheet()
            },
            IntegrationManageAction(
                systemImage: "lock",
                title: "Manage permissions",
                iconTint: .accent
            ) {
                openPermissionsFromManageSheet()
            }
        ]
    }

    private func connectAppleHealth() {
        actionTask?.cancel()
        isConnecting = true
        actionTask = Task {
            let didConnect = await importCoordinator.requestAppleHealthAuthorizationIfNeeded()
            await MainActor.run {
                isConnecting = false

                if didConnect {
                    if importCoordinator.pendingCount > 0 {
                        showingImportSheet = true
                    }
                } else if let errorMessage = importCoordinator.lastErrorMessage, !errorMessage.isEmpty {
                    presentError(errorMessage)
                }
            }
        }
    }

    private func triggerManualSyncFromManageSheet() {
        showingManageSheet = false
        actionTask?.cancel()
        actionTask = Task {
            await importCoordinator.refreshPendingImports(trigger: .manualSync)
            if let errorMessage = importCoordinator.lastErrorMessage, !errorMessage.isEmpty {
                await MainActor.run {
                    presentError(errorMessage)
                }
            }
        }
    }

    private func queueImportReviewFromManageSheet() {
        actionTask?.cancel()
        actionTask = Task {
            await importCoordinator.refreshPendingImports(trigger: .manualReview)
            await MainActor.run {
                if let errorMessage = importCoordinator.lastErrorMessage, !errorMessage.isEmpty {
                    presentError(errorMessage)
                    shouldPresentImportsAfterManageDismiss = false
                } else {
                    shouldPresentImportsAfterManageDismiss = true
                }
                showingManageSheet = false
            }
        }
    }

    private func openPermissionsFromManageSheet() {
        showingManageSheet = false
        openHealthApp()
    }

    private func presentImportsAfterManageSheetDismissal() {
        guard shouldPresentImportsAfterManageDismiss else { return }
        shouldPresentImportsAfterManageDismiss = false
        showingImportSheet = true
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

#Preview("Light Theme") {
    AppleHealthIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.light)
        .modelContainer(for: [Workout.self, WorkoutSourceLink.self], inMemory: true)
}

#Preview("Dark Theme") {
    AppleHealthIntegrationCard()
        .padding()
        .themedBackground()
        .preferredColorScheme(.dark)
        .modelContainer(for: [Workout.self, WorkoutSourceLink.self], inMemory: true)
}
