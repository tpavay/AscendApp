//
//  KeyboardDismissButton.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/12/25.
//

import SwiftUI

/// A button that dismisses the keyboard when tapped.
/// Use with `ToolbarItem(placement: .keyboard)` in a toolbar.
struct KeyboardDismissButton: View {
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack {
            Spacer()
            Button {
                hideKeyboard()
            } label: {
                Text("Done")
                    .font(.montserratSemiBold(size: 16))
            }
        }
    }

    private func hideKeyboard() {
        onDismiss()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

#Preview {
    KeyboardDismissButton()
}
