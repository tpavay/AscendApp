////
////  SignUpView.swift
////  AscendApp
////
////  Created by Tyler Pavay on 8/9/25.
////
//
//import AuthenticationServices
//import SwiftUI
//
//struct SignUpView: View {
//    // The authVM instance was created in isolated to the main actor within the root of our app.
//    @Environment(AuthenticationViewModel.self) private var authVM
//    @Environment(\.dismiss) private var dismiss
//
//    var body: some View {
//        ZStack {
//            // Same gradient as landing screen
//            LinearGradient(colors: [.night, .jetLighter],
//                           startPoint: .topLeading,
//                           endPoint: .bottomTrailing)
//                .ignoresSafeArea()
//
//            VStack(spacing: 24) {
//                // App icon for continuity
//                Image("AppIconInternal")
//                    .resizable()
//                    .renderingMode(.template)
//                    .foregroundStyle(.accent)
//                    .frame(width: 80, height: 80)
//                    .shadow(color: .accent.opacity(0.35), radius: 16, y: 6)
//                    .padding(.top, 120)
//
//                VStack(spacing: 0) {
//                    Text("LOGIN TO")
//                        .font(.custom("Montserrat-Bold", size: 36, relativeTo: .largeTitle))
//                        .foregroundStyle(.white)
//                        .multilineTextAlignment(.center)
//                        .lineLimit(nil)
//                        .kerning(0.5)
//                        .shadow(color: .white.opacity(0.6), radius: 2)
//                    Text("CONNECT")
//                        .font(.custom("Montserrat-Bold", size: 36, relativeTo: .largeTitle))
//                        .foregroundStyle(.white)
//                        .multilineTextAlignment(.center)
//                        .lineLimit(nil)
//                        .kerning(0.5)
//                        .shadow(color: .white.opacity(0.6), radius: 2)
//                }
//
//                Text("Connect your account to track your stairmaster progress and sync across all your devices")
//                    .font(.montserratLight)
//                    .foregroundStyle(.white.opacity(0.72))
//                    .multilineTextAlignment(.center)
//                    .padding(.horizontal, 32)
//                    .padding(.bottom, 16)
//
//                VStack(spacing: 16) {
//                    // Apple Sign In Button with accent styling
//                    Button(action: {}) {
//                        HStack(spacing: 12) {
//                            Image(systemName: "apple.logo")
//                                .font(.system(size: 24, weight: .medium))
//
//                            Text("Continue with Apple")
//                                .font(.montserratSemiBold)
//                        }
//                        .foregroundStyle(.white)
//                        .frame(maxWidth: .infinity)
//                        .frame(height: 55)
//                        .background(
//                            RoundedRectangle(cornerRadius: 14)
//                                .fill(.accent.darker(by: 0.15))
//                        )
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 14)
//                                .stroke(.accent, lineWidth: 1)
//                        )
//                    }
//
//                    // Google Sign In Button with secondary styling
//                    Button(action: {
//                        Task { // Tasks inherit isolation context. So, because we are in a View
//                            // this task is isolated to the main actor.
//
//                            // Sending self.authVM risks causing data races. This is because the signInWithGoogle function
//                            // defined in the authVM (isolated to main actor) is called a function that is not isolated
//                            // to the main actor. So, if state is modified within the non isolated context
//                            // it could cause data races.
//                            await authVM.signInWithGoogle()
//                        }
//                    }) {
//                        HStack(spacing: 12) {
//                            Image("GoogleIcon")
//                                .frame(width: 18, height: 18)
//                                .foregroundStyle(.white)
//
//                            Text("Continue with Google")
//                                .font(.montserratSemiBold)
//                        }
//                        .foregroundStyle(.white)
//                        .frame(maxWidth: .infinity)
//                        .frame(height: 55)
//                        .background(
//                            RoundedRectangle(cornerRadius: 14)
//                                .fill(.white.opacity(0.1))
//                        )
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 14)
//                                .stroke(.white.opacity(0.3), lineWidth: 1)
//                        )
//                    }
//                }
//                .padding(.horizontal, 24)
//
//                Spacer()
//
//                // Terms and privacy text
//                Text("By continuing, you agree to our Terms of Service and Privacy Policy")
//                    .font(.montserratLight)
//                    .foregroundStyle(.white.opacity(0.5))
//                    .multilineTextAlignment(.center)
//                    .padding(.horizontal, 40)
//                    .padding(.bottom, 40)
//            }
//        }
//    }
//}
//
//#Preview {
//    NavigationStack {
//        SignUpView()
//            .environment(AuthenticationViewModel())
//    }
//}


//
//  SignUpView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/9/25.
//

import AuthenticationServices
import SwiftUI

struct SignUpView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Same gradient as landing screen
            LinearGradient(colors: [.night, .jetLighter],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()

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
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .kerning(0.5)
                        .shadow(color: .white.opacity(0.6), radius: 2)
                    Text("CONNECT")
                        .font(.custom("Montserrat-Bold", size: 36, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .kerning(0.5)
                        .shadow(color: .white.opacity(0.6), radius: 2)
                }

                Text("Connect your account to track your stairmaster progress and sync across all your devices")
                    .font(.montserratLight)
                    .foregroundStyle(.white.opacity(0.72))
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
                    Button(action: {}) {
                        HStack(spacing: 12) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 24, weight: .medium))

                            Text("Continue with Apple")
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

                    // Google Sign In Button with secondary styling
                    Button(action: { Task {
                        await authVM.signInWithGoogle()
                    } }) {
                        HStack(spacing: 12) {
                            if authVM.authenticationState == .authenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image("GoogleIcon")
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.white)
                            }

                            Text(authVM.authenticationState == .authenticating ? "Signing In..." : "Continue with Google")
                                .font(.montserratSemiBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(authVM.authenticationState == .authenticating)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Terms and privacy text
                Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                    .font(.montserratLight)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(AuthenticationViewModel())
    }
}
