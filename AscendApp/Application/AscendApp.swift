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
    let authService: AuthenticationService

    init() {
        FirebaseApp.configure()
        authService = AuthenticationService.shared
    }

    var body: some Scene {
        WindowGroup {
            if (authService.isAuthenticated) {
                HomeView()
            }
            else {
                LoginSignUpView()
            }
        }
    }
}
