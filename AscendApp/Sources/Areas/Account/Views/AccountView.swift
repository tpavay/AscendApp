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
                // Profile Section
                VStack(spacing: 16) {
                    // Profile Picture
                    AsyncImage(url: authVM.photoURL) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                Circle()
                                    .fill(.jetLighter.opacity(0.3))
                                    .frame(width: 120, height: 120)

                                Image(systemName: "person.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 2)
                                )
                        case .failure:
                            ZStack {
                                Circle()
                                    .fill(.jetLighter.opacity(0.3))
                                    .frame(width: 120, height: 120)

                                Image(systemName: "person.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        @unknown default:
                            ZStack {
                                Circle()
                                    .fill(.jetLighter.opacity(0.3))
                                    .frame(width: 120, height: 120)

                                Image(systemName: "person.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(width: 120, height: 120)

                    // Display Name
                    Text(authVM.displayName.isEmpty ? "No Name Set" : authVM.displayName)
                        .font(.montserratSemiBold)
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Settings Section
                VStack(spacing: 16) {
                    // Account Settings Card
                    VStack(spacing: 0) {
                        settingsRow(icon: "person.circle", title: "Edit Profile", action: {
                            // TODO: Navigate to edit profile
                        })

                        Divider()
                            .background(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))

                        settingsRow(icon: "bell", title: "Notifications", action: {
                            // TODO: Navigate to notifications
                        })

                        Divider()
                            .background(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))

                        NavigationLink(destination: ThemeSelectionView()) {
                            HStack(spacing: 16) {
                                Image(systemName: "paintbrush")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.accent)
                                    .frame(width: 24, height: 24)
                                
                                Text("Appearance")
                                    .font(.montserratMedium)
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }

                        Divider()
                            .background(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))

                        settingsRow(icon: "lock", title: "Privacy", action: {
                            // TODO: Navigate to privacy
                        })
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.jetLighter.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                    )

                    // Sign Out Button
                    Button(action: {
                        authVM.signOut()
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18, weight: .medium))
                            Text("Sign Out")
                                .font(.montserratSemiBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.red.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.top, 8)
                }

                if let errorMessage = authVM.errorMessage {
                    Text(errorMessage)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
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
    
    private func settingsRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.accent)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.montserratMedium)
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
    
    private func settingsRowContent(icon: String, title: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.accent)
                .frame(width: 24, height: 24)
            
            Text(title)
                .font(.montserratMedium)
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}


#Preview {
    NavigationStack {
        AccountView()
            .environment(AuthenticationViewModel())
    }
}
