import SwiftUI

extension View {
    func keyboardDoneToolbar(onDismiss: @escaping () -> Void = {}) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                KeyboardDismissButton(onDismiss: onDismiss)
            }
        }
    }
}
