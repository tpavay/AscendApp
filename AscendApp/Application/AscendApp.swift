//
//  AscendApp.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import FirebaseCore
import SwiftUI

@main
struct AscendApp: App {
    @State private var authService: AuthenticationService

    init() {
        FirebaseApp.configure()
        authService = AuthenticationService.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if (authService.isAuthenticated) {
                    HomeView()
                }
                else {
                    LoginSignUpView()
                }
            }.animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
                .environment(authService)
        }
    }
}
