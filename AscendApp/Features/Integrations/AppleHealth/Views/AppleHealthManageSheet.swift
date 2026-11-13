//
//  AppleHealthManageSheet.swift
//  AscendApp
//
//  Created by Codex on 4/20/26.
//

import SwiftUI

/// Settings -> Integrations -> Apple Health -> Manage: everything a connected climber can change
/// about Apple Health, in the one place Settings keeps it.
///
/// The two import rows show only while Health is connected for import, so they are absent with
/// the import kill switch off, and Import older workouts has the history switch of its own.
struct AppleHealthManageSheet: View {
    @Binding var isPresented: Bool

    @State private var importService: AppleHealthImportService
    @State private var showingOlderWorkouts = false

    let onCheckNow: () -> Void
    let onOpenHealthPermissions: () -> Void

    static let autoImportDetail = "New stair stepper workouts become climbs on their own."
    static let olderWorkoutsDetail = "Add the ones from before you joined to your history."

    init(
        isPresented: Binding<Bool>,
        importService: AppleHealthImportService = .shared,
        onCheckNow: @escaping () -> Void,
        onOpenHealthPermissions: @escaping () -> Void
    ) {
        _isPresented = isPresented
        _importService = State(initialValue: importService)
        self.onCheckNow = onCheckNow
        self.onOpenHealthPermissions = onOpenHealthPermissions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IntegrationManageHeader(assetImage: "appleHealth-icon", title: "Apple Health")

            VStack(spacing: 12) {
                if importService.offeredImportConnectionState == .connected {
                    IntegrationManageToggleRow(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "Import automatically",
                        subtitle: Self.autoImportDetail,
                        isOn: Binding(
                            get: { importService.isAutoImportEnabled },
                            set: { isEnabled in
                                Task { await importService.setAutoImportEnabled(isEnabled) }
                            }
                        )
                    )

                    if importService.offersOlderWorkouts {
                        manageActionButton(
                            systemImage: "clock.arrow.circlepath",
                            title: "Import older workouts",
                            subtitle: Self.olderWorkoutsDetail,
                            action: { showingOlderWorkouts = true }
                        )
                    }
                }

                manageActionButton(
                    systemImage: "arrow.clockwise",
                    title: "Check for heart rate now",
                    action: onCheckNow
                )

                manageActionButton(
                    systemImage: "heart.text.square",
                    title: "Manage Health permissions",
                    action: onOpenHealthPermissions
                )
            }

            Button("Close") {
                isPresented = false
            }
            .appSheetButtonStyle(tone: .subtle)
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .appSheetBackground()
        .appSheetStyle(.actionMenu)
        // Over the sheet rather than in its place, so closing the history screen lands back here.
        .fullScreenCover(isPresented: $showingOlderWorkouts) {
            AppleHealthOlderWorkoutsView(
                viewModel: AppleHealthOlderWorkoutsViewModel(importService: importService),
                onClose: { showingOlderWorkouts = false }
            )
        }
        .trackOnce(screen: .appleHealthManage)
    }

    private func manageActionButton(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            IntegrationManageActionRow(
                action: IntegrationManageAction(
                    systemImage: systemImage,
                    title: title,
                    subtitle: subtitle,
                    iconTint: .accent,
                    action: action
                )
            )
        }
        .buttonStyle(.plain)
    }
}
