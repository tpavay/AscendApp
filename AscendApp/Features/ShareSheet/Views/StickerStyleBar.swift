import SwiftUI

/// Font, Color and Shadow, each showing its value; one setting applies to every sticker at once.
struct StickerStyleBar: View {
    let model: StickersViewModel

    var body: some View {
        HStack(spacing: 8) {
            button(.font, title: "FONT", value: model.style.font.title) {
                Text("Aa")
                    .presetText(model.style.font.presetFont, size: 20, weight: 900, color: .white)
            }
            button(.color, title: "COLOR", value: model.style.color.title) {
                Circle()
                    .fill(Color(shareHex: model.style.color.hex))
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                    .frame(width: 22, height: 22)
            }
            button(.shadow, title: "SHADOW", value: model.style.shadow.title) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func button<Icon: View>(
        _ panel: StickersViewModel.Panel,
        title: String,
        value: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let open = model.panel == panel
        return Button {
            HapticsManager.shared.trigger(.selection)
            model.togglePanel(panel)
        } label: {
            HStack(spacing: 8) {
                icon()
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.montserratBold(size: 9))
                        .tracking(1.2)
                        .foregroundStyle(Color(shareHex: 0xA3A3A3))
                    Text(value)
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(shareHex: 0x141414)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(open ? Color(shareHex: PresetAccent.lime.hex) : Color(shareHex: 0x1E1E1E), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title.capitalized): \(value)")
    }
}
