//
//  AccountView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/19/25.
//

import SwiftUI

struct AccountView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Account View")
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}

#Preview {
    AccountView()
}
