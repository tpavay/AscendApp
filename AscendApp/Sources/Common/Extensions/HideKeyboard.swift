//
//  HideKeyboard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

// MARK: - Keyboard Dismissal Extension
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            hideKeyboard()
        }
    }
}
