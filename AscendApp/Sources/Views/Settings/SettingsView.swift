//
//  SettingsView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/17/25.
//

import SwiftUI

struct SettingsView: View {
    @State var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    Button(action: viewModel.signOut, label: {
                        Text("Log Out")
                            .foregroundStyle(.accent)
                            .fontWeight(.bold)
                    })
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.black)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.accent, lineWidth: 1)
                    )
                    .padding()
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
