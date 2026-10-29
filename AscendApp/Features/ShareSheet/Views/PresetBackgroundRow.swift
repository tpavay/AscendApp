import SwiftUI

/// The Background panel's scrolling row. The row keeps its place when a tile is chosen and opens
/// with the current choice in view, so the selected background is never off the screen.
struct PresetBackgroundRow: View {
    let model: PresetsViewModel
    let onChoosePhoto: () -> Void

    private let lime = Color(shareHex: PresetAccent.lime.hex)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.seasonalBackgrounds) { seasonal in
                        tile(
                            id: "seasonal.\(seasonal.rawValue)",
                            title: seasonal.title,
                            selected: model.background == .seasonal(seasonal),
                            seasonalDot: true,
                            background: .seasonal(seasonal)
                        ) { model.selectSeasonal(seasonal) }
                    }
                    if model.hasTower {
                        tile(id: "tower", title: "Tower", selected: model.background == .tower, background: .tower) {
                            model.selectTower()
                        }
                    }
                    photoTile
                    ForEach(PresetFlatBackground.allCases) { flat in
                        tile(
                            id: "flat.\(flat.rawValue)",
                            title: flat.title,
                            selected: model.background == .flat(flat),
                            background: .flat(flat)
                        ) { model.selectBackground(flat) }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onAppear {
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
    }

    private var selectedID: String {
        switch model.background {
        case .flat(let flat): return "flat.\(flat.rawValue)"
        case .tower: return "tower"
        case .photo: return "photo"
        case .seasonal(let seasonal): return "seasonal.\(seasonal.rawValue)"
        }
    }

    private var photoTile: some View {
        Button {
            HapticsManager.shared.trigger(.selection)
            onChoosePhoto()
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(shareHex: 0x3A3A3A), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color(shareHex: 0xD4D4D4))
                    )
                    .overlay {
                        if model.background == .photo {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(lime, lineWidth: 2).padding(-2)
                        }
                    }
                Text("Photo")
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(model.background == .photo ? .white : Color(shareHex: 0x8A8A8A))
            }
        }
        .buttonStyle(.plain)
        .id("photo")
        .accessibilityLabel("Choose a photo background")
    }

    private func tile(
        id: String,
        title: String,
        selected: Bool,
        seasonalDot: Bool = false,
        background: PresetCardBackground,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticsManager.shared.trigger(.selection)
            action()
        } label: {
            VStack(spacing: 5) {
                PresetBackgroundThumb(model: model.swatchModel(for: background), artwork: model.artwork, size: 46)
                    .overlay(alignment: .topTrailing) {
                        if seasonalDot {
                            Circle().fill(lime).frame(width: 8, height: 8).padding(3)
                        }
                    }
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(lime, lineWidth: 2).padding(-2)
                        }
                    }
                Text(title)
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(selected ? .white : Color(shareHex: 0x8A8A8A))
                    .lineLimit(1)
            }
            .frame(minWidth: 46)
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityLabel("\(title) background")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
