//
//  ModeToggleView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct ModeToggleView: View {
    let viewModel: AuthenticationViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: { 
                if !viewModel.isLogin {
                    viewModel.toggleMode()
                }
            }) {
                Text("Log In")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(viewModel.isLogin ? .black : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(viewModel.isLogin ? .accent : Color.clear)
                    .cornerRadius(12)
            }
            
            Button(action: { 
                if viewModel.isLogin {
                    viewModel.toggleMode()
                }
            }) {
                Text("Sign Up")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(!viewModel.isLogin ? .black : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(!viewModel.isLogin ? .accent : Color.clear)
                    .cornerRadius(12)
            }
        }
        .padding(4)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

#Preview {
    @Previewable @State var viewModel = AuthenticationViewModel()
    
    return ModeToggleView(viewModel: viewModel)
        .padding()
        .background(Color.black)
}
