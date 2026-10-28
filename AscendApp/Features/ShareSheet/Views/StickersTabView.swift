import SwiftUI

/// The Stickers tab: This climb or Totals, a scope menu, a two-column grid of stickers, and the
/// shared Font, Color and Shadow controls.
struct StickersTabView: View {
    let model: StickersViewModel
    let sheet: ShareSheetViewModel

    @State private var activeItem: StickerItem?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            hint
                .padding(.top, 8)
            scopeRow
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(model.items) { item in
                        StickerTile(
                            item: item,
                            subject: model.subject,
                            totals: model.totals,
                            style: model.style,
                            year: model.seasonalYear,
                            isActive: activeItem == item,
                            onCopy: { copy(item) },
                            onSave: { save(item) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 10) {
                if model.panel != nil {
                    StickerStylePanel(model: model)
                }
                StickerStyleBar(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(Color(shareHex: 0x1A1A1A)).frame(height: 1)
            }
        }
        .task(id: model.scope == .totals ? model.period : nil) {
            guard model.scope == .totals else { return }
            await model.loadTotals()
        }
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.on.square")
            Text("Tap to copy")
            Text("·").foregroundStyle(Color(shareHex: 0x4A4A4A))
            Image(systemName: "arrow.down.to.line")
            Text("Hold to save")
        }
        .font(.montserratSemiBold(size: 13))
        .foregroundStyle(Color(shareHex: 0xA3A3A3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tap a sticker to copy it. Hold to save it to Photos.")
    }

    private var scopeRow: some View {
        HStack {
            HStack(spacing: 2) {
                segment("This climb", selected: model.scope == .climb) { model.scope = .climb }
                segment("Totals", selected: model.scope == .totals) { model.scope = .totals }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(shareHex: 0x151515)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(shareHex: 0x1E1E1E), lineWidth: 1))

            Spacer()

            if model.scope == .totals {
                Menu {
                    ForEach(SharePeriod.allCases) { period in
                        Button(period.menuTitle) { model.period = period }
                    }
                } label: {
                    menuLabel(model.period.menuTitle)
                }
            } else {
                menuLabel(model.climbScopeTitle)
            }
        }
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
        }
        .font(.montserratSemiBold(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .overlay(Capsule().stroke(Color(shareHex: 0x2A2A2A), lineWidth: 1))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticsManager.shared.trigger(.selection)
            action()
        } label: {
            Text(title)
                .font(selected ? .montserratBold(size: 13) : .montserratSemiBold(size: 13))
                .foregroundStyle(selected ? .white : Color(shareHex: 0x8A8A8A))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color(shareHex: 0x2A2A2A) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Actions

    private func rendered(_ item: StickerItem) -> UIImage? {
        sheet.shareExporter.renderSticker(
            StickerItemView(
                item: item,
                subject: model.subject,
                totals: model.totals,
                style: model.style,
                year: model.seasonalYear
            )
        )
    }

    private func copy(_ item: StickerItem) {
        flash(item)
        sheet.copySticker(rendered(item))
    }

    private func save(_ item: StickerItem) {
        flash(item)
        let image = rendered(item)
        Task { await sheet.saveSticker(image) }
    }

    private func flash(_ item: StickerItem) {
        activeItem = item
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            if activeItem == item { activeItem = nil }
        }
    }
}
