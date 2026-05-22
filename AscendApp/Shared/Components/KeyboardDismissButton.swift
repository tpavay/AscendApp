//
//  KeyboardDismissButton.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/12/25.
//

import SwiftUI

/// A plain button that dismisses the keyboard when tapped.
/// Prefer `.keyboardDoneToolbar` for screen-level keyboard dismissal.
struct KeyboardDismissButton: View {
    var onDismiss: () -> Void = {}

    var body: some View {
        Button {
            hideKeyboard()
        } label: {
            Text("Done")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func hideKeyboard() {
        onDismiss()
        KeyboardAccessoryDismissAction.dismissKeyboard()
    }
}

#Preview {
    KeyboardDismissButton()
}
