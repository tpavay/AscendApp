import SwiftUI

/// Background, Font, Stats and Accent, each showing its current value. Tapping one opens its
/// panel above the bar; tapping it again closes the panel.
struct PresetCustomizationBar: View {
    let model: PresetsViewModel

    var body: some View {
        let card = model.cardModel
        HStack(spacing: 6) {
            button("Background", panel: .background) {
                HStack(spacing: 5) {
                    PresetBackgroundThumb(background: model.background, accent: model.preferences.accent)
                        .frame(width: 11, height: 11)
                    Text(model.background.title)
                }
            }
            button("Font", panel: .font) {
                HStack(spacing: 5) {
                    Text("Aa")
                        .presetText(model.preferences.font, size: 11, weight: 900, color: .white)
                    Text(model.preferences.font.title)
                }
            }
            button("Stats", panel: .stats) {
                Text("\(model.shownStatCount) shown")
            }
            button("Accent", panel: .accent) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(shareHex: card.accent.hex))
                        .frame(width: 10, height: 10)
                    Text(card.accent.title)
                }
            }
        }
    }

    private func button<Value: View>(
        _ title: String,
        panel: PresetsViewModel.Panel,
        @ViewBuilder value: () -> Value
    ) -> some View {
        let isOpen = model.panel == panel
        return Button {
            HapticsManager.shared.trigger(.selection)
            model.togglePanel(panel)
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.montserratBold(size: 11))
                    .foregroundStyle(.white)
                value()
                    .font(.montserratSemiBold(size: 10))
                    .foregroundStyle(Color(shareHex: 0xA3A3A3))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(shareHex: 0x151515)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isOpen ? Color(shareHex: PresetAccent.lime.hex) : Color(shareHex: 0x1E1E1E), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(isOpen ? "open" : "closed")")
    }
}
