//
//  TermsAndPrivacyView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct TermsAndPrivacyView: View {
    let viewModel: AuthenticationViewModel
    
    var body: some View {
        VStack(spacing: 4) {
            Text("By creating an account, you agree to our")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack(spacing: 4) {
                Button("Terms of Service") {
                    viewModel.openTermsOfService()
                }
                .font(.caption)
                .foregroundColor(.accent)
                
                Text("and")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Button("Privacy Policy") {
                    viewModel.openPrivacyPolicy()
                }
                .font(.caption)
                .foregroundColor(.accent)
            }
        }
    }
}

#Preview {
    @Previewable @State var viewModel = AuthenticationViewModel()
    
    return TermsAndPrivacyView(viewModel: viewModel)
        .padding()
        .background(Color.black)
}
