//
//  SettingsView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/17/25.
//

import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            VStack {
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
