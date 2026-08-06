import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsView: View {
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isClimbDropEnabled = ClimbDropNotificationPreferenceStore.isEnabled
    @State private var isUpdating = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if authorizationStatus == .denied {
                    notificationsDisabledBanner
                }

                ProfileSection(title: "Climbs") {
                    ProfileCardSurface {
                        climbDropRow
                    }
                }

                if authorizationStatus != .denied {
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
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .themedBackground()
        .navigationTitle("Push")
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
        .onReceive(NotificationCenter.default.publisher(for: .climbDropNotificationPreferenceDidChange)) { _ in
            isClimbDropEnabled = ClimbDropNotificationPreferenceStore.isEnabled
        }
    }

    private var climbDropRow: some View {
        HStack(spacing: 16) {
            AppIcon(token: .settingsNotifications, pointSize: 22, weight: .medium)
                .foregroundStyle(.accent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("New climb drops")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)

                Text("A new landmark opens in the catalog.")
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(
                "",
                isOn: Binding(
                    get: { isClimbDropEnabled },
                    set: { isEnabled in
                        Task {
                            await setClimbDropEnabled(isEnabled)
                        }
                    }
                )
            )
            .labelsHidden()
            .tint(.accent)
            .disabled(isUpdating || authorizationStatus == .denied)
            .accessibilityLabel("New climb drops")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isUpdating ? 0.68 : authorizationStatus == .denied ? 0.45 : 1)
    }

    private var notificationsDisabledBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications are off in iOS")
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(.white)

                Text("Ascend can't send anything until you turn them back on.")
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open iOS Settings") {
                    ClimbDropNotificationPermissionController.openSystemNotificationSettings()
                }
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(.accent)
                .frame(minHeight: 44)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                }
        )
        .accessibilityElement(children: .combine)
    }

    private var permissionStatusRow: some View {
        HStack(spacing: 16) {
            AppIcon(token: .settingsNotifications, pointSize: 22, weight: .medium)
                .foregroundStyle(permissionColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

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
            ClimbDropNotificationPermissionController.openSystemNotificationSettings()
        } label: {
            HStack(spacing: 16) {
                AppIcon(token: .settingsNotifications, pointSize: 22, weight: .medium)
                    .foregroundStyle(.accent)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

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
        authorizationStatus = await ClimbDropNotificationPermissionController.authorizationStatus()
        isClimbDropEnabled = ClimbDropNotificationPreferenceStore.isEnabled

        if authorizationStatus == .denied && isClimbDropEnabled {
            await ClimbDropNotificationPermissionController.disable()
            isClimbDropEnabled = false
        }
    }

    private func setClimbDropEnabled(_ isEnabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        if isEnabled {
            authorizationStatus = await ClimbDropNotificationPermissionController.enable()
        } else {
            await ClimbDropNotificationPermissionController.disable()
            authorizationStatus = await ClimbDropNotificationPermissionController.authorizationStatus()
        }

        isClimbDropEnabled = ClimbDropNotificationPreferenceStore.isEnabled
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
