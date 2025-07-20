//
//  SettingsViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/19/25.
//

@MainActor
class SettingsViewModel {
    private let authService = AuthenticationService.shared

    func signOut() {
        do {
            try authService.signOut()
        }
        catch {
            print("ERROR: There was an error signing out")
        }
    }
}
