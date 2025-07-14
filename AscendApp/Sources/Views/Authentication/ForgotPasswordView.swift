//
//  ForgotPasswordView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct ForgotPasswordView: View {
    let viewModel: AuthenticationViewModel
    
    var body: some View {
        Button(action: {
            viewModel.forgotPassword()
        }) {
            Text("Forgot Password?")
                .font(.subheadline)
                .foregroundColor(.accent)
        }
    }
}

#Preview {
    @Previewable @State var viewModel = AuthenticationViewModel()
    
    return ForgotPasswordView(viewModel: viewModel)
        .padding()
        .background(Color.black)
}
