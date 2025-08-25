//
//  AccountView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI

struct AccountView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [.night, .jetLighter], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack {
                AsyncImage(url: authVM.photoURL) { phase in
                    switch phase {
                    case .empty:
                        Image(systemName: "person")
                            .foregroundStyle(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(Circle())
                    case .failure:
                        Image(systemName: "person")
                    @unknown default:
                        Image(systemName: "person")
                    }
                }
                Button(action: {
                    authVM.signOut()
                }) {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                        .frame(height: 55)
                        .foregroundStyle(.white)
                        .font(.montserratRegular)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.red)
                        )
                }
                if let errorMessage = authVM.errorMessage {
                    Text(errorMessage)
                        .font(.montserratSemiBold)
                        .foregroundStyle(.red)
                }

            }
            .padding()
        }
        .navigationTitle("Account")
        .toolbarBackground(.green, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .onChange(of: authVM.authenticationState) { oldValue, newValue in
            if newValue == .unauthenticated {
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environment(AuthenticationViewModel())
    }
}
