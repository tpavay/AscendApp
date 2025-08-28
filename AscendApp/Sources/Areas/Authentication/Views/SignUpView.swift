import AuthenticationServices
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
                        .foregroundColor(.red)
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
                    .disabled(authVM.authenticationState == .authenticatingWithApple ||
                              authVM.authenticationState ==  .authenticatingWithGoogle)

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
                    .disabled(authVM.authenticationState == .authenticatingWithApple ||
                              authVM.authenticationState == .authenticatingWithGoogle)
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
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(AuthenticationViewModel())
    }
}
