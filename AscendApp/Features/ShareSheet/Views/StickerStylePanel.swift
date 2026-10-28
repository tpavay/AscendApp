import SwiftUI

/// The panel above the style bar: the open setting's choices, with Done.
struct StickerStylePanel: View {
    let model: StickersViewModel

    private let lime = Color(shareHex: PresetAccent.lime.hex)

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.montserratBold(size: 11))
                    .tracking(1.5)
                    .foregroundStyle(Color(shareHex: 0xA3A3A3))
                Spacer()
                Button {
                    model.panel = nil
                } label: {
                    Text("Done")
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(lime))
                }
            }
            switch model.panel {
            case .font: fonts
            case .color: colors
            case .shadow: shadows
            case nil: EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(shareHex: 0x141414)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(shareHex: 0x222222), lineWidth: 1))
    }

    private var title: String {
        switch model.panel {
        case .font: return "FONT"
        case .color: return "COLOR"
        case .shadow: return "SHADOW"
        case nil: return ""
        }
    }

    private var fonts: some View {
        HStack(spacing: 6) {
            ForEach(StickerStyle.Font.allCases) { font in
                option(font.title, selected: model.style.font == font) {
                    model.setFont(font)
                } label: {
                    Text("5,004").presetText(font.presetFont, size: 16, weight: 900, color: .white)
                }
            }
        }
    }

    private var colors: some View {
        HStack {
            ForEach(StickerStyle.Color.allCases) { color in
                let selected = model.style.color == color
                Button {
                    HapticsManager.shared.trigger(.selection)
                    model.setColor(color)
                } label: {
                    Circle()
                        .fill(Color(shareHex: color.hex))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                        .overlay(Circle().stroke(lime, lineWidth: selected ? 2 : 0).padding(-4))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var shadows: some View {
        HStack(spacing: 6) {
            ForEach(StickerStyle.Shadow.allCases) { shadow in
                option(shadow.title, selected: model.style.shadow == shadow) {
                    model.setShadow(shadow)
                } label: {
                    Text(shadow.title)
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func option<Label: View>(
        _ name: String,
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            HapticsManager.shared.trigger(.selection)
            action()
        } label: {
            VStack(spacing: 2) {
                label()
                Text(name)
                    .font(.montserratSemiBold(size: 9))
                    .foregroundStyle(Color(shareHex: 0xA3A3A3))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(shareHex: 0x1C1C1C)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? lime : Color(shareHex: 0x262626), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
