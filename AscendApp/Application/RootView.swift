//
//  RootView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    var body: some View {
        Group {
            switch authVM.authenticationState {
            case .authenticated:
                HomeView()
            case .authenticatingWithApple,
                .authenticatingWithGoogle:
                ProgressView("Signing In...")
            case .unauthenticated:
                LandingScreen()
            }
        }.animation(.easeInOut(duration: 0.25), value: authVM.authenticationState)
    }
}

#Preview {
    RootView()
        .environment(AuthenticationViewModel())
}
