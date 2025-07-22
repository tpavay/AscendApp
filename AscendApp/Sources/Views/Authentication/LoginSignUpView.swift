//
//  LoginSignUpView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct LoginSignUpView: View {
    @State private var viewModel = AuthenticationViewModel()

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 32) {
                        AppLogoView()
                            .padding(.top, 40)

                        AuthenticationFormView()

                        if !viewModel.isLogin {
                            TermsAndPrivacyView(viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50) // Extra padding for keyboard
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color.black)
            .navigationBarHidden(true)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isLogin)
        }
    }
}

#Preview {
    LoginSignUpView()
}
