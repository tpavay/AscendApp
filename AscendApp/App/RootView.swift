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

    var body: some View {
        Group {
            switch authVM.authenticationState {
            case .authenticated, .restoringSession:
                MainTabView()
            case .authenticatingWithApple,
                 .authenticatingWithGoogle:
                ProgressView("Signing In...")
                    .themedBackground()
            case .unauthenticated:
                LandingScreen()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authVM.authenticationState)
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
