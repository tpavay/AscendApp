//
//  DeleteAccountButton.swift
//  AscendApp
//

import SwiftUI

struct DeleteAccountButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .medium))

                Text("Delete Account")
                    .font(.montserratSemiBold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.red)
            )
        }
    }
}

#Preview {
    DeleteAccountButton(action: {})
        .padding()
        .themedBackground()
}
