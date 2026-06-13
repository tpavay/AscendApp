import SwiftUI

extension View {
    func keyboardDoneToolbar(onDismiss: @escaping () -> Void = {}) -> some View {
        keyboardAccessoryToolbar {
            Spacer(minLength: 0)

            Button {
                onDismiss()
                KeyboardAccessoryDismissAction.dismissKeyboard()
            } label: {
                KeyboardDoneAccessoryLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
    }

    func keyboardAccessoryToolbar<AccessoryContent: View>(
        @ViewBuilder content: @escaping () -> AccessoryContent
    ) -> some View {
        modifier(KeyboardAccessoryToolbarModifier(accessoryContent: content))
    }
}

private struct KeyboardAccessoryToolbarModifier<AccessoryContent: View>: ViewModifier {
    let accessoryContent: () -> AccessoryContent

    @State private var keyboardFrame: CGRect = .zero
    @State private var isKeyboardVisible = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    if isKeyboardVisible {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            KeyboardAccessoryBar {
                                accessoryContent()
                            }
                                .padding(.bottom, keyboardOverlap(in: proxy))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    }
                }
                .allowsHitTesting(isKeyboardVisible)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                updateKeyboardState(from: notification, isVisible: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardState(from: notification, isVisible: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                updateKeyboardState(from: notification, isVisible: false)
            }
    }

    private func keyboardOverlap(in proxy: GeometryProxy) -> CGFloat {
        guard isKeyboardVisible else { return 0 }
        let viewBottom = proxy.frame(in: .global).maxY
        return max(0, viewBottom - keyboardFrame.minY)
    }

    private func updateKeyboardState(from notification: Notification, isVisible: Bool) {
        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25

        withAnimation(.easeOut(duration: duration)) {
            keyboardFrame = frame
            isKeyboardVisible = isVisible && frame.height > 0
        }
    }
}

enum KeyboardAccessoryDismissAction {
    @MainActor
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct KeyboardAccessoryBar<AccessoryContent: View>: View {
    @ViewBuilder let accessoryContent: () -> AccessoryContent

    var body: some View {
        HStack(spacing: 16) {
            accessoryContent()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Color.black.opacity(0.88))
    }
}

struct KeyboardDoneAccessoryLabel: View {
    var body: some View {
        Text("Done")
            .font(.montserratSemiBold(size: 16))
            .foregroundStyle(Color.ascendAccent)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
    }
}
