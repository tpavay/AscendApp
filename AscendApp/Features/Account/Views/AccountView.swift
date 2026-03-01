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
    
    @State private var isShowingEditProfile = false
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

                sectionView(title: "Profile", options: profileOptions)
                sectionView(title: "Support", options: supportOptions)
                sectionView(title: "Developer", options: developerOptions)

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
        #endif

        return options
    }

    private var supportOptions: [SettingsOption] {
        [
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
