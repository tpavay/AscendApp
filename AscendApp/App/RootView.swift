//
//  RootView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.modelContext) private var modelContext
    @Environment(MediaUploadManager.self) private var uploadManager
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
        .task {
            // Resume any pending uploads from previous session
            await uploadManager.processPendingUploads(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Retry pending uploads when app comes to foreground (network may have restored)
            Task {
                await uploadManager.processPendingUploads(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthenticationViewModel())
}
