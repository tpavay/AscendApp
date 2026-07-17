import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsView: View {
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isClimbDropEnabled = ClimbDropNotificationPreferenceStore.isEnabled
    @State private var isUpdating = false
    @State private var emailPreferences = EmailPreferencesViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileSection(title: "Climb Drops") {
                    ProfileCardSurface {
                        climbDropRow
                    }
                }

                ProfileSection(title: "Emails") {
                    ProfileCardSurface {
                        emailRow
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
        .task {
            await emailPreferences.load()
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

            VStack(alignment: .leading, spacing: 4) {
                Text("New climb drops")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)

                Text("Get an Ascend alert when new climbs open.")
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isUpdating ? 0.68 : 1)
    }

    private var emailRow: some View {
        HStack(spacing: 16) {
            AppIcon(token: .settingsContactUs, pointSize: 22, weight: .medium)
                .foregroundStyle(.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Climb and progress emails")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)

                Text(emailSubtitle)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(emailSubtitleColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            // The view model stays the single source of truth for the switch:
            // it reverts itself when a write fails, and the unsubscribe link
            // can change the stored value from outside the app.
            Toggle(
                "Climb and progress emails",
                isOn: Binding(
                    get: { emailPreferences.isLifecycleEmailsEnabled },
                    set: { isEnabled in
                        Task {
                            await emailPreferences
                                .setLifecycleEmailsEnabled(isEnabled)
                        }
                    }
                )
            )
            .labelsHidden()
            .tint(.accent)
            .disabled(emailPreferences.isToggleDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(emailPreferences.isUpdating ? 0.68 : 1)
    }

    private var emailSubtitle: String {
        if let errorMessage = emailPreferences.errorMessage {
            return errorMessage
        }

        switch emailPreferences.loadState {
        case .loading:
            return "Checking your email settings…"
        case .ready, .failed:
            return "Account and security emails always come through."
        }
    }

    private var emailSubtitleColor: Color {
        emailPreferences.errorMessage == nil
            ? .white.opacity(0.64)
            : .orange
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
            ClimbDropNotificationPermissionController.openSystemNotificationSettings()
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
