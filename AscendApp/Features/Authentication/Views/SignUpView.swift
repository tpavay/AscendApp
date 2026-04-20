import AuthenticationServices
import FirebaseCore
import SwiftUI

struct SignUpView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
                // App icon for continuity
                Image("AppIconInternal")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.accent)
                    .frame(width: 80, height: 80)
                    .shadow(color: .accent.opacity(0.35), radius: 16, y: 6)
                    .padding(.top, 120)

                VStack(spacing: 0) {
                    Text("LOGIN TO")
                        .font(.custom("Montserrat-Bold", size: 36, relativeTo: .largeTitle))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .kerning(0.5)
                        .shadow(color: colorScheme == .dark ? .white.opacity(0.6) : .clear, radius: 2)
                    Text("CONNECT")
                        .font(.custom("Montserrat-Bold", size: 36, relativeTo: .largeTitle))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .kerning(0.5)
                        .shadow(color: colorScheme == .dark ? .white.opacity(0.6) : .clear, radius: 2)
                }

                Text("Connect your account to track your stair climbing progress and sync across all your devices")
                    .font(.montserratLight)
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : .gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                // Show error message if any
                if let errorMessage = authVM.errorMessage {
                    Text(errorMessage)
                        .font(.montserratRegular)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 32)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    // Apple Sign In Button with accent styling
                    Button(action: { Task {
                        await authVM.signInWithApple()
                        if authVM.authenticationState == .authenticated {
                            dismiss()
                        }
                    } }) {
                        HStack(spacing: 12) {
                            if authVM.authenticationState == .authenticatingWithApple {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 24, weight: .medium))
                            }

                            Text(authVM.authenticationState == .authenticatingWithApple ? "Signing In..." : "Continue with Apple")
                                .font(.montserratSemiBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.accent.darker(by: 0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.accent, lineWidth: 1)
                        )
                    }
                    .disabled(authVM.authenticationState.isAuthenticating)

                    // Google Sign In Button with secondary styling
                    Button(action: { Task {
                        await authVM.signInWithGoogle()
                        if authVM.authenticationState == .authenticated
                        {
                            dismiss()
                        }
                    } }) {
                        HStack(spacing: 12) {
                            if authVM.authenticationState == .authenticatingWithGoogle {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image("GoogleIcon")
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                            }

                            Text(authVM.authenticationState == .authenticatingWithGoogle ? "Signing In..." : "Continue with Google")
                                .font(.montserratSemiBold)
                        }
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(colorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(authVM.authenticationState.isAuthenticating)

                    if canShowInternalQASignIn {
                        NavigationLink(destination: InternalQASignInView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.badge.key")
                                    .font(.system(size: 18, weight: .semibold))

                                Text("Internal QA Sign In")
                                    .font(.montserratSemiBold)

                                Spacer()

                                Text("Dev/Staging")
                                    .font(.montserratSemiBold(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.14))
                                    )
                            }
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(colorScheme == .dark ? Color.orange.opacity(0.12) : Color.orange.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.orange.opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 1)
                            )
                        }
                        .disabled(authVM.authenticationState.isAuthenticating)

                        Text("Internal QA sign-in uses a real Firebase account and is only available in dev and staging builds.")
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Terms and privacy text
                Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                    .font(.montserratLight)
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
        }
        .themedBackground()
    }

    private var canShowInternalQASignIn: Bool {
        InternalQASignInAvailability.isEnabled(
            projectID: FirebaseApp.app()?.options.projectID
        )
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(AuthenticationViewModel())
    }
}
