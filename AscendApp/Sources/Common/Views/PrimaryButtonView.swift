//
//  PrimaryButtonView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct PrimaryButtonView: View {
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        title: String,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                }
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isEnabled ? .accent : .gray)
            .cornerRadius(16)
        }
        .disabled(!isEnabled || isLoading)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButtonView(
            title: "Log In",
            isEnabled: true,
            isLoading: false
        ) {
            print("Button tapped")
        }
        
        PrimaryButtonView(
            title: "Loading...",
            isEnabled: true,
            isLoading: true
        ) {
            print("Button tapped")
        }
        
        PrimaryButtonView(
            title: "Disabled",
            isEnabled: false,
            isLoading: false
        ) {
            print("Button tapped")
        }
    }
    .padding()
    .background(Color.black)
}
