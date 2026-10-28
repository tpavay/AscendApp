import SwiftUI

/// A white pill with a black check, shown above the bottom controls and cleared by the view model.
struct ShareSheetToastView: View {
    let message: String?
    /// The bottom controls are taller while a panel is open, so the toast rides above them.
    let raised: Bool

    var body: some View {
        ZStack {
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(shareHex: PresetAccent.lime.hex))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.black))
                    Text(message)
                        .font(.montserratSemiBold(size: 13))
                        .foregroundStyle(.black)
                }
                .padding(.leading, 9)
                .padding(.trailing, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color(shareHex: 0xF5F5F4)))
                .padding(.bottom, raised ? 200 : 100)
                .transition(.opacity)
                .onAppear {
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.18), value: message)
        .allowsHitTesting(false)
    }
}
