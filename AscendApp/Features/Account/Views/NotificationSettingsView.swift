import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @State private var notificationState: ClimbDropNotificationState

    init(notificationState: ClimbDropNotificationState = .shared) {
        _notificationState = State(initialValue: notificationState)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if notificationState.authorizationStatus == .denied {
                    notificationsDisabledBanner
                }

                ProfileSection(title: "Climbs") {
                    ProfileCardSurface {
                        climbDropRow
                    }
                }

                if notificationState.authorizationStatus != .denied {
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
            await notificationState.refreshIfNeeded()
        }
    }

    /// Turning the preference off is always the climber's to make here and needs nothing from iOS,
    /// so the switch stays. Turning it back on while iOS refuses delivery cannot finish on this
    /// screen, so that one direction carries the screen's own Open iOS Settings affordance instead
    /// of a switch that would flip, store an answer, and walk out.
    @ViewBuilder
    private var climbDropRow: some View {
        if notificationState.authorizationStatus == .denied, notificationState.isPreferenceEnabled == false {
            Button {
                Task {
                    await setClimbDropEnabled(true)
                }
            } label: {
                climbDropRowContent {
                    AppIcon(token: .disclosureChevronRight, pointSize: 14, weight: .medium)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(notificationState.isUpdating)
            .accessibilityHint("Turns these on and opens iOS Settings")
        } else {
            climbDropRowContent {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { notificationState.isPreferenceEnabled },
                        set: { isEnabled in
                            Task {
                                await setClimbDropEnabled(isEnabled)
                            }
                        }
                    )
                )
                .labelsHidden()
                .tint(.accent)
                .disabled(notificationState.isUpdating)
                .accessibilityLabel("New climb drops")
            }
        }
    }

    private func climbDropRowContent<Trailing: View>(
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 16) {
            AppIcon(token: .settingsNotifications, pointSize: 22, weight: .medium)
                .foregroundStyle(.accent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("New climb drops")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.white)

                Text(climbDropDetail)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(notificationState.isBlockedBySystemSettings ? Color.orange : Color.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(notificationState.isUpdating ? 0.68 : 1)
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
                    notificationState.openSystemNotificationSettings()
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
            notificationState.openSystemNotificationSettings()
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

    /// The stored preference stays exactly as the climber set it while iOS is refusing delivery,
    /// so the row reports its own status rather than letting an on toggle read as deliverable.
    /// The banner above carries the explanation and the route into iOS Settings.
    private var climbDropDetail: String {
        if notificationState.isBlockedBySystemSettings {
            return "On, but iOS is blocking delivery"
        }

        if notificationState.authorizationStatus == .denied {
            return "Off. Allow notifications in iOS first."
        }

        return "A new landmark opens in the catalog."
    }

    private var shouldShowSystemSettingsAction: Bool {
        guard let authorizationStatus = notificationState.authorizationStatus else { return false }

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
        guard let authorizationStatus = notificationState.authorizationStatus else {
            return "Checking permission"
        }

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
        guard let authorizationStatus = notificationState.authorizationStatus else {
            return .white.opacity(0.64)
        }

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

    private func setClimbDropEnabled(_ isEnabled: Bool) async {
        if isEnabled {
            await notificationState.enable()
        } else {
            await notificationState.disable()
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
