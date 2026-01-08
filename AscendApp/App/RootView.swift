//
//  RootView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @AppStorage("hasCompletedFitnessOnboarding") private var hasCompletedFitnessOnboarding = false

    var body: some View {
        Group {
            switch authVM.authenticationState {
            case .authenticated, .restoringSession:
                if hasCompletedFitnessOnboarding {
                    MainTabView()
                } else {
                    FitnessLevelOnboardingView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hasCompletedFitnessOnboarding = true
                        }
                    }
                }
            case .authenticatingWithApple,
                 .authenticatingWithGoogle:
                ProgressView("Signing In...")
                    .themedBackground()
            case .unauthenticated:
                LandingScreen()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authVM.authenticationState)
        .animation(.easeInOut(duration: 0.25), value: hasCompletedFitnessOnboarding)
        .themeAware()
    }
}

#Preview {
    RootView()
        .environment(AuthenticationViewModel())
}
