//
//  HomeView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI

struct HomeView: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    var body: some View {
        VStack {
            HStack {
                Text("Welcome \(authVM.displayName)")
                    .font(.montserratSemiBold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                NavigationLink(destination: AccountView()) {
                    Image(systemName: "person")
                }
            }
            Spacer()
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AuthenticationViewModel())
    }
}
