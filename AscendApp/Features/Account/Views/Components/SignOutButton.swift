//
//  SignOutButton.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import SwiftUI

struct SignOutButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .medium))
                
                Text("Sign Out")
                    .font(.montserratSemiBold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.red.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.red.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
}

#Preview {
    SignOutButton(action: {})
        .padding()
        .themedBackground()
}
