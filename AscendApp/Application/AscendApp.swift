//
//  AscendApp.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import FirebaseCore
import SwiftUI
import SwiftData

@main
struct AscendApp: App {
    @State private var authVM: AuthenticationViewModel

    init() {
        FirebaseApp.configure()
        authVM = AuthenticationViewModel()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootView()
            }
        }
        .environment(authVM)
        .modelContainer(for: [Workout.self])
    }
}
