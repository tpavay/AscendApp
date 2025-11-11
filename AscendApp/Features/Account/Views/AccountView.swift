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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Header
                ProfileHeaderView(
                    photoURL: authVM.photoURL,
                    displayName: authVM.displayName
                )

                // Settings Sections
                settingsContent

                // Error Message
                if let errorMessage = authVM.errorMessage {
                    errorMessageView(errorMessage)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .themedBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
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
                    // TODO: Navigate to edit profile
                }
            ),
            SettingsOption(
                icon: "bell",
                title: "Notifications",
                action: {
                    // TODO: Navigate to notifications
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

        options.append(
            SettingsOption(
                icon: "lock",
                title: "Privacy",
                action: {
                    // TODO: Navigate to privacy
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
