import SwiftUI

/// The panel that opens above the customisation bar: Reset and Done, then the open tool's controls.
struct PresetPanelView: View {
    let model: PresetsViewModel
    let onChoosePhoto: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.montserratBold(size: 11))
                    .tracking(1.5)
                    .foregroundStyle(Color(shareHex: 0xA3A3A3))
                Spacer()
                Button("Reset") {
                    HapticsManager.shared.trigger(.lightImpact)
                    model.reset()
                }
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(Color(shareHex: 0xA3A3A3))
                .padding(.horizontal, 10)
                Button {
                    model.panel = nil
                } label: {
                    Text("Done")
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color(shareHex: PresetAccent.lime.hex)))
                }
            }
            switch model.panel {
            case .background:
                PresetBackgroundRow(model: model, onChoosePhoto: onChoosePhoto)
            case .font:
                fontGrid
            case .stats:
                PresetStatsPanel(model: model)
            case .accent:
                accentRow
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(shareHex: 0x141414)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(shareHex: 0x222222), lineWidth: 1))
    }

    private var title: String {
        switch model.panel {
        case .background: return "BACKGROUND"
        case .font: return "FONT"
        case .stats: return "STATS ON THIS PRESET"
        case .accent: return "ACCENT COLOR"
        case nil: return ""
        }
    }

    private var fontGrid: some View {
        HStack(spacing: 6) {
            ForEach(PresetFont.allCases) { font in
                let selected = model.preferences.font == font
                Button {
                    HapticsManager.shared.trigger(.selection)
                    model.setFont(font)
                } label: {
                    VStack(spacing: 2) {
                        Text("5,004")
                            .presetText(font, size: 18, weight: 900, color: .white)
                        Text(font.title)
                            .font(.montserratSemiBold(size: 9))
                            .foregroundStyle(Color(shareHex: 0xA3A3A3))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(shareHex: 0x1C1C1C)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected ? Color(shareHex: PresetAccent.lime.hex) : Color(shareHex: 0x262626), lineWidth: selected ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(font.title) font")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var accentRow: some View {
        HStack {
            ForEach(PresetAccent.allCases) { accent in
                let selected = model.preferences.accent == accent
                Button {
                    HapticsManager.shared.trigger(.selection)
                    model.setAccent(accent)
                } label: {
                    Circle()
                        .fill(Color(shareHex: accent.hex))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color(shareHex: 0x141414), lineWidth: selected ? 2 : 0).padding(-2))
                        .overlay(Circle().stroke(Color(shareHex: PresetAccent.lime.hex), lineWidth: selected ? 2 : 0).padding(-4))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(accent.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}
