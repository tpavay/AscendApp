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
    @State private var settingsManager = SettingsManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var showingManageSheet = false
    @State private var showingImportSheet = false
    @State private var shouldPresentImportsAfterManageDismiss = false
    @State private var actionTask: Task<Void, Never>?
    @State private var isConnecting = false
    @State private var isConfiguringDefaultAutoImport = false
    @State private var alertMessage = ""
    @State private var showingErrorAlert = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    private var connectionState: AppleHealthConnectionState {
        importCoordinator.appleHealthConnectionState
    }

    private var pendingCount: Int {
        importCoordinator.appleHealthAttentionCount
    }

    private var autoImportEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.appleHealthAutoImportEnabled },
            set: { settingsManager.setAppleHealthAutoImportEnabled($0) }
        )
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
            AppleHealthManageSheet(
                isPresented: $showingManageSheet,
                autoImportEnabled: autoImportEnabledBinding,
                attentionCount: pendingCount,
                onSyncNow: triggerManualSyncFromManageSheet,
                onReviewImports: queueImportReviewFromManageSheet,
                onOpenHealthPermissions: openPermissionsFromManageSheet
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
        .onChange(of: settingsManager.appleHealthAutoImportEnabled) { _, _ in
            guard !isConfiguringDefaultAutoImport else { return }
            handleAutoImportToggleChanged()
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
        case .unavailable:
            return nil
        case .neverConnected:
            return nil
        case .connected:
            return settingsManager.appleHealthAutoImportEnabled ? "Connected • Auto-Import On" : "Connected"
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
            if settingsManager.appleHealthAutoImportEnabled {
                return "New Apple Health workouts import automatically and stay ready for quick review in Ascend."
            }
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

    private func connectAppleHealth() {
        actionTask?.cancel()
        isConnecting = true
        actionTask = Task {
            let didConnect = await importCoordinator.requestAppleHealthAuthorizationIfNeeded()
            guard didConnect else {
                await MainActor.run {
                    isConnecting = false

                    if let errorMessage = importCoordinator.lastErrorMessage, !errorMessage.isEmpty {
                        presentError(errorMessage)
                    }
                }
                return
            }

            await MainActor.run {
                isConnecting = false
                isConfiguringDefaultAutoImport = true
                settingsManager.setAppleHealthAutoImportEnabled(true)
            }
            await importCoordinator.handleAppleHealthAutoImportPreferenceChanged()
            await MainActor.run {
                isConfiguringDefaultAutoImport = false
                showingImportSheet = importCoordinator.pendingCount > 0
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
            let resolution = await importCoordinator.prepareImportInbox()
            await MainActor.run {
                if let errorMessage = importCoordinator.lastErrorMessage, !errorMessage.isEmpty {
                    presentError(errorMessage)
                    shouldPresentImportsAfterManageDismiss = false
                } else {
                    shouldPresentImportsAfterManageDismiss = resolution == .showImportSheet
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

    private func handleAutoImportToggleChanged() {
        actionTask?.cancel()
        actionTask = Task {
            await importCoordinator.handleAppleHealthAutoImportPreferenceChanged()
        }
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
