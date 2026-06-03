import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isTodayClimbDropEnabled = TodayClimbNotificationPreferenceStore.isEnabled
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileSection(title: "Climb Drops") {
                    ProfileCardSurface {
                        todayClimbDropRow
                    }
                }

                ProfileSection(title: "System") {
                    ProfileCardSurface {
                        VStack(spacing: 0) {
                            permissionStatusRow

                            if shouldShowSystemSettingsAction {
                                ProfileCardDivider()
                                systemSettingsButton
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .themedBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task {
            await refreshAuthorizationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await refreshAuthorizationStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todayClimbNotificationPreferenceDidChange)) { _ in
            isTodayClimbDropEnabled = TodayClimbNotificationPreferenceStore.isEnabled
        }
    }

    private var todayClimbDropRow: some View {
        HStack(spacing: 16) {
            AppIcon(token: .settingsNotifications, pointSize: 22, weight: .medium)
                .foregroundStyle(.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("4 AM climb drop")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)

                Text("One alert when today's climb changes.")
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(
                "",
                isOn: Binding(
                    get: { isTodayClimbDropEnabled },
                    set: { isEnabled in
                        Task {
                            await setTodayClimbDropEnabled(isEnabled)
                        }
                    }
                )
            )
            .labelsHidden()
            .tint(.accent)
            .disabled(isUpdating || authorizationStatus == .denied)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isUpdating ? 0.68 : 1)
    }

    private var permissionStatusRow: some View {
        HStack(spacing: 16) {
            AppIcon(token: .settingsNotifications, pointSize: 22, weight: .medium)
                .foregroundStyle(permissionColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("iOS permission")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)

                Text(permissionLabel)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(permissionColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var systemSettingsButton: some View {
        Button {
            TodayClimbNotificationPermissionController.openSystemNotificationSettings()
        } label: {
            HStack(spacing: 16) {
                AppIcon(token: .settingsNotifications, pointSize: 22, weight: .medium)
                    .foregroundStyle(.accent)
                    .frame(width: 28, height: 28)

                Text("Open iOS Settings")
                    .font(.montserratMedium)
                    .foregroundStyle(.white)

                Spacer()

                AppIcon(token: .disclosureChevronRight, pointSize: 14, weight: .medium)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shouldShowSystemSettingsAction: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral, .denied:
            return true
        case .notDetermined:
            return false
        @unknown default:
            return true
        }
    }

    private var permissionLabel: String {
        switch authorizationStatus {
        case .authorized:
            return "Allowed"
        case .provisional:
            return "Quiet alerts allowed"
        case .ephemeral:
            return "Allowed"
        case .denied:
            return "Off in iOS Settings"
        case .notDetermined:
            return "Not asked yet"
        @unknown default:
            return "Unknown"
        }
    }

    private var permissionColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .accent
        case .denied:
            return .orange
        case .notDetermined:
            return .white.opacity(0.64)
        @unknown default:
            return .white.opacity(0.64)
        }
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await TodayClimbNotificationPermissionController.authorizationStatus()
        isTodayClimbDropEnabled = TodayClimbNotificationPreferenceStore.isEnabled

        if authorizationStatus == .denied && isTodayClimbDropEnabled {
            await TodayClimbNotificationPermissionController.disable()
            isTodayClimbDropEnabled = false
        }
    }

    private func setTodayClimbDropEnabled(_ isEnabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }

        if isEnabled {
            let input = notificationScheduleInput()
            authorizationStatus = await TodayClimbNotificationPermissionController.enable(
                availableClimbs: input.availableClimbs,
                completedClimbIds: input.completedClimbIds
            )
        } else {
            await TodayClimbNotificationPermissionController.disable()
            authorizationStatus = await TodayClimbNotificationPermissionController.authorizationStatus()
        }

        isTodayClimbDropEnabled = TodayClimbNotificationPreferenceStore.isEnabled
    }

    private func notificationScheduleInput() -> (availableClimbs: [Climb], completedClimbIds: Set<String>) {
        do {
            return (
                availableClimbs: try ClimbService.shared.loadAvailableClimbs(),
                completedClimbIds: ClimbService.shared.completedClimbIds(modelContext: modelContext)
            )
        } catch {
            errorMessage = "Notifications are on, but climbs could not be scheduled yet."
            return (availableClimbs: [], completedClimbIds: [])
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
