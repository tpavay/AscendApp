//
//  AccountView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI

struct AccountView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isShowingEditProfile = false
    @State private var isShowingDeleteAccountConfirmation = false

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
                icon: "person.circle",
                title: "Edit Profile",
                action: {
                    isShowingEditProfile = true
                }
            ),
            SettingsOption(
                icon: "paintbrush",
                title: "Appearance",
                destination: ThemeSelectionView()
            ),
            SettingsOption(
                icon: "chart.bar.fill",
                title: "Workout Metric",
                destination: WorkoutMetricSelectionView()
            ),
            SettingsOption(
                icon: "ruler",
                title: "Measurement System",
                destination: MeasurementSystemSelectionView()
            ),
            SettingsOption(
                icon: "link",
                title: "Integrations",
                destination: IntegrationsView()
            )
        ]

        #if DEBUG
        options.append(
            SettingsOption(
                icon: "hammer.fill",
                title: "Debug Tools",
                iconColor: .orange,
                destination: DebugToolsView()
            )
        )
        #endif

        // Contact Us - before destructive actions
        options.append(
            SettingsOption(
                icon: "envelope",
                title: "Contact Us",
                destination: ContactUsView()
            )
        )

        // Delete Account - destructive action at the end
        options.append(
            SettingsOption(
                icon: "trash",
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
