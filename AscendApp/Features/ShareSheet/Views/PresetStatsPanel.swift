import SwiftUI

/// The stat chips, then the best-effort picker when the climb earned more than one.
struct PresetStatsPanel: View {
    let model: PresetsViewModel

    private let lime = Color(shareHex: PresetAccent.lime.hex)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShareChipFlowLayout(spacing: 6) {
                chip("Steps · always on", on: false, locked: true) {}
                ForEach(model.availableStats) { stat in
                    chip(stat.title, on: model.preferences.isOn(stat)) {
                        HapticsManager.shared.trigger(.selection)
                        model.toggle(stat)
                    }
                }
            }
            if model.preferences.isOn(.bestEfforts), model.subject.bestEfforts.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        pick("Count · \(model.subject.bestEfforts.count)", selected: model.pickedBestEffortID == nil) {
                            model.pickBestEffort(nil)
                        }
                        ForEach(model.subject.bestEfforts) { effort in
                            pick("\(effort.rankText) · \(effort.title)", selected: model.pickedBestEffortID == effort.id) {
                                model.pickBestEffort(effort.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, locked: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(locked ? title : (on ? "✓ " : "+ ") + title)
                .font(.montserratBold(size: 12))
                .foregroundStyle(locked ? Color(shareHex: 0x8A8A8A) : (on ? lime : Color(shareHex: 0xA3A3A3)))
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(Capsule().fill(Color(shareHex: locked ? 0x1A1A1A : (on ? 0x1F2A10 : 0x1A1A1A))))
                .overlay(Capsule().stroke(locked ? Color(shareHex: 0x2A2A2A) : (on ? lime : Color(shareHex: 0x2A2A2A)), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pick(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticsManager.shared.trigger(.selection)
            action()
        } label: {
            Text(title)
                .font(.montserratBold(size: 11))
                .foregroundStyle(selected ? lime : Color(shareHex: 0xA3A3A3))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color(shareHex: selected ? 0x1F2A10 : 0x1A1A1A)))
                .overlay(Capsule().stroke(selected ? lime : Color(shareHex: 0x2A2A2A), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
