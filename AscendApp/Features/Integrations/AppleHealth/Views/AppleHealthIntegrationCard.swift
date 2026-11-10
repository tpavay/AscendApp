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
    @State private var importService = AppleHealthImportService.shared
    @State private var showingManageSheet = false
    @State private var showingConnectFlow = false
    @State private var showingImports = false
    /// Set when the connect flow finished, so Imports opens once its cover is gone.
    @State private var opensImportsAfterConnect = false
    @State private var actionTask: Task<Void, Never>?
    @State private var alertMessage = ""
    @State private var showingErrorAlert = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: systemColorScheme)
    }

    private var status: AppleHealthIntegrationStatus {
        AppleHealthIntegrationStatus(
            enrichment: enrichmentService.appleHealthConnectionState,
            importState: importService.offeredImportConnectionState
        )
    }

    var body: some View {
        let style = IntegrationCardStyle(effectiveColorScheme: effectiveColorScheme)
        let status = self.status

        IntegrationCardShell(style: style) {
            IntegrationCardHeader(
                assetImage: "appleHealth-icon",
                title: "Apple Health",
                subtitle: status.label,
                titleColor: style.primaryText,
                subtitleColor: statusColor(status.tone)
            ) {
                headerAction(status.action)
            }

            IntegrationCardDescriptionSection(
                style: style,
                text: status.message
            )
        }
        .sheet(isPresented: $showingManageSheet) {
            AppleHealthManageSheet(
                isPresented: $showingManageSheet,
                importService: importService,
                onCheckNow: checkForHeartRateFromManageSheet,
                onOpenHealthPermissions: openPermissionsFromManageSheet
            )
        }
        .fullScreenCover(isPresented: $showingConnectFlow, onDismiss: {
            guard opensImportsAfterConnect else { return }
            opensImportsAfterConnect = false
            showingImports = true
        }) {
            AppleHealthConnectFlowView(
                onFinished: {
                    opensImportsAfterConnect = true
                    showingConnectFlow = false
                },
                onClose: { showingConnectFlow = false }
            )
        }
        .fullScreenCover(isPresented: $showingImports) {
            NavigationStack {
                AppleHealthImportsView()
            }
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
    private func headerAction(_ action: AppleHealthIntegrationStatus.Action) -> some View {
        switch action {
        case .none:
            EmptyView()
        case .connect:
            IntegrationCardActionButton(
                "Connect",
                appearance: .filled(background: .accent, foreground: .black)
            ) {
                showingConnectFlow = true
            }
        case .manage:
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

    private func statusColor(_ tone: AppleHealthIntegrationStatus.Tone) -> Color {
        switch tone {
        case .connected:
            return .accent
        case .disabled:
            return .orange
        case .neutral:
            return .secondary
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
