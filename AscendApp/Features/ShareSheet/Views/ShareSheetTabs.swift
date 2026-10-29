import SwiftUI

/// The two tabs, Presets and Stickers, as 44 pt pills.
struct ShareSheetTabs: View {
    @Binding var selection: ShareSheetViewModel.Tab
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            pill("Presets", tab: .presets)
            pill("Stickers", tab: .stickers)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    private func pill(_ title: String, tab: ShareSheetViewModel.Tab) -> some View {
        let selected = selection == tab
        return Button {
            guard selection != tab else { return }
            HapticsManager.shared.trigger(.selection)
            selection = tab
        } label: {
            Text(title)
                .font(selected ? .montserratBold(size: 15) : .montserratSemiBold(size: 15))
                .foregroundStyle(selected ? accent : Color(shareHex: 0xA3A3A3))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(shareHex: selected ? 0x1E1E1E : 0x151515))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(shareHex: selected ? 0x2E2E2E : 0x1E1E1E), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
