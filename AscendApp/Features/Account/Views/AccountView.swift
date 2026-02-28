//
//  AccountView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import FirebaseCore
import SwiftUI

struct AccountView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isShowingEditProfile = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var isShowingPrivacyPolicy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Header
                ProfileHeaderView(
                    photoURL: authVM.displayPhotoURL,
                    displayName: authVM.displayName,
                    onEditTap: {
                        isShowingEditProfile = true
                    }
                )

                // Settings Sections
                settingsContent

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
        .navigationBarTitleDisplayMode(.large)
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
        .sheet(isPresented: $isShowingDeleteAccountConfirmation) {
            DeleteAccountConfirmationView(
                onAccountDeleted: {
                    // The auth state listener will automatically handle navigation
                    // back to the landing screen when the account is deleted
                }
            )
        }
        .onChange(of: authVM.authenticationState) { oldValue, newValue in
            if newValue == .unauthenticated {
                dismiss()
            }
        }
    }

    // MARK: - Settings Content

    @ViewBuilder
    private var settingsContent: some View {
        VStack(spacing: 16) {
            // Main Settings Card
            SettingsCard(options: settingsOptions)

            // Sign Out Button
            SignOutButton(action: authVM.signOut)
                .padding(.top, 8)
        }
    }

    // MARK: - Settings Options Configuration

    private var settingsOptions: [SettingsOption] {
        var options: [SettingsOption] = [
            SettingsOption(
                icon: .settingsEditProfile,
                title: "Edit Profile",
                action: {
                    isShowingEditProfile = true
                }
            ),
            SettingsOption(
                icon: .settingsAppearance,
                title: "Appearance",
                destination: ThemeSelectionView()
            ),
            SettingsOption(
                icon: .settingsWorkoutMetric,
                title: "Workout Metric",
                destination: WorkoutMetricSelectionView()
            ),
            SettingsOption(
                icon: .settingsMeasurementSystem,
                title: "Measurement System",
                destination: MeasurementSystemSelectionView()
            ),
            SettingsOption(
                icon: .settingsIntegrations,
                title: "Integrations",
                destination: IntegrationsView()
            )
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
        #endif

        // Privacy Policy
        options.append(
            SettingsOption(
                icon: .settingsPrivacyPolicy,
                title: "Privacy Policy",
                action: {
                    isShowingPrivacyPolicy = true
                }
            )
        )

        // Contact Us - before destructive actions
        options.append(
            SettingsOption(
                icon: .settingsContactUs,
                title: "Contact Us",
                destination: ContactUsView()
            )
        )

        // Delete Account - destructive action at the end
        options.append(
            SettingsOption(
                icon: .settingsDeleteAccount,
                title: "Delete Account",
                isDestructive: true,
                action: {
                    isShowingDeleteAccountConfirmation = true
                }
            )
        )

        return options
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
