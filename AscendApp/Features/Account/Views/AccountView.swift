//
//  AccountView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import FirebaseCore
import StoreKit
import SwiftUI

struct AccountView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    
    @State private var isShowingEditProfile = false
    @State private var isShowingTermsOfService = false
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingSignOutConfirmation = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var isShowingManageSubscriptions = false
    @State private var restorePurchases = RestorePurchasesViewModel()

    var body: some View {
        @Bindable var restorePurchases = restorePurchases

        ScrollView {
            VStack(spacing: 24) {
                // Profile Header
                ProfileHeaderView(
                    photoURL: authVM.displayPhotoURL,
                    displayName: authVM.displayName,
                    email: authVM.user?.email,
                    onEditTap: {
                        isShowingEditProfile = true
                    }
                )

                sectionView(title: "Profile", options: profileOptions)
                sectionView(title: "Notifications", options: notificationOptions)
                sectionView(title: "Preferences", options: preferenceOptions)
                sectionView(title: "Subscription", options: subscriptionOptions)
                sectionView(title: "Support", options: supportOptions)
                sectionView(title: "Privacy", options: privacyOptions)
                sectionView(title: "Developer", options: developerOptions)

                SignOutButton {
                    isShowingSignOutConfirmation = true
                }

                DeleteAccountButton {
                    isShowingDeleteAccountConfirmation = true
                }

                // Error Message
                if let errorMessage = authVM.errorMessage {
                    errorMessageView(errorMessage)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .themedBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isShowingEditProfile) {
            EditProfileView()
        }
        .sheet(isPresented: $isShowingPrivacyPolicy) {
            if let projectId = FirebaseApp.app()?.options.projectID,
               let url = URL(string: "https://\(projectId).web.app/privacy") {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $isShowingTermsOfService) {
            if let projectId = FirebaseApp.app()?.options.projectID,
               let url = URL(string: "https://\(projectId).web.app/terms") {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        // Apple's own sheet, not a hand-rolled apps.apple.com URL: it is the only surface that can
        // cancel, change, or resubscribe a plan without leaving Ascend.
        .manageSubscriptionsSheet(isPresented: $isShowingManageSubscriptions)
        .sheet(isPresented: $isShowingDeleteAccountConfirmation) {
            DeleteAccountConfirmationView(
                onAccountDeleted: {
                    dismiss()
                }
            )
        }
        .alert(
            "Sign Out",
            isPresented: $isShowingSignOutConfirmation,
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                authVM.signOut()
            }
        } message: {
            Text("You'll need to sign back in to access your account.")
        }
        .alert(item: $restorePurchases.result) { result in
            Alert(
                title: Text(result.title),
                message: result.message.map { Text($0) },
                dismissButton: .default(Text("Done"))
            )
        }
        .onChange(of: authVM.authenticationState) { oldValue, newValue in
            if newValue == .unauthenticated {
                dismiss()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(title: String, options: [SettingsOption]) -> some View {
        if !options.isEmpty {
            ProfileSection(title: title) {
                SettingsCard(options: options)
            }
        }
    }

    private var profileOptions: [SettingsOption] {
        [
            SettingsOption(
                icon: .settingsEditProfile,
                title: "Edit Profile",
                action: {
                    isShowingEditProfile = true
                }
            )
        ]
    }

    private var notificationOptions: [SettingsOption] {
        [
            SettingsOption(
                icon: .settingsNotifications,
                title: "Push",
                destination: NotificationSettingsView()
            ),
            SettingsOption(
                icon: .settingsContactUs,
                title: "Email",
                destination: EmailPreferencesView()
            )
        ]
    }

    private var preferenceOptions: [SettingsOption] {
        [
            SettingsOption(
                icon: .settingsMeasurementSystem,
                title: "Units",
                destination: MeasurementSystemSelectionView()
            ),
            SettingsOption(
                icon: .settingsIntegrations,
                title: "Integrations",
                destination: IntegrationsView()
            )
        ]
    }

    private var developerOptions: [SettingsOption] {
        var options: [SettingsOption] = [
        ]

        #if DEBUG
        options.append(
            SettingsOption(
                icon: .settingsDebugTools,
                title: "Debug Tools",
                iconColor: .orange,
                destination: DebugToolsView()
            )
        )
        #elseif STAGING
        // QA runs on Staging TestFlight, where the rest of Debug Tools is compiled out. Remote Flags
        // still ships here on its own so a thrown kill switch can be watched landing on the build
        // under test - a switch nobody can verify is the failure this branch exists to prevent.
        options.append(
            SettingsOption(
                icon: .settingsDebugTools,
                title: "Remote Flags",
                iconColor: .orange,
                destination: RemoteFeatureFlagsView()
            )
        )
        #endif

        return options
    }

    private var subscriptionOptions: [SettingsOption] {
        [
            SettingsOption(
                icon: .settingsManageSubscription,
                title: "Manage Subscription",
                action: {
                    isShowingManageSubscriptions = true
                }
            ),
            SettingsOption(
                icon: .settingsRestorePurchases,
                title: restorePurchases.isRestoring ? "Restoring Purchases…" : "Restore Purchases",
                isEnabled: restorePurchases.isRestoreAvailable && !restorePurchases.isRestoring,
                isLoading: restorePurchases.isRestoring,
                action: {
                    Task {
                        await restorePurchases.restorePurchases()
                    }
                }
            )
        ]
    }

    private var supportOptions: [SettingsOption] {
        [
            SettingsOption(
                icon: .settingsTermsOfService,
                title: "Terms of Service",
                action: {
                    isShowingTermsOfService = true
                }
            ),
            SettingsOption(
                icon: .settingsPrivacyPolicy,
                title: "Privacy Policy",
                action: {
                    isShowingPrivacyPolicy = true
                }
            ),
            SettingsOption(
                icon: .settingsContactUs,
                title: "Contact Us",
                destination: ContactUsView()
            )
        ]
    }

    private var privacyOptions: [SettingsOption] {
        [
            SettingsOption(
                icon: .settingsBlockedClimbers,
                title: "Blocked climbers",
                destination: BlockedClimbersView()
            )
        ]
    }

    // MARK: - Error Message View

    private func errorMessageView(_ message: String) -> some View {
        Text(message)
            .font(.montserratRegular(size: 14))
            .foregroundStyle(.red.opacity(0.9))
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environment(AuthenticationViewModel())
    }
}
