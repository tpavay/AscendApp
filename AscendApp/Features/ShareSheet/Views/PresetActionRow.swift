import SwiftUI

/// Story (the primary action), Copy, Save and More.
struct PresetActionRow: View {
    let isBusy: Bool
    let perform: (ShareSheetViewModel.CardAction) -> Void

    var body: some View {
        HStack {
            action("Story", action: .story, primary: true) { InstagramGlyph().foregroundStyle(.black) }
            action("Copy", action: .copy) { Image(systemName: "square.on.square").font(.system(size: 20, weight: .semibold)) }
            action("Save", action: .save) { Image(systemName: "arrow.down.to.line").font(.system(size: 20, weight: .semibold)) }
            action("More", action: .more) { Image(systemName: "square.and.arrow.up").font(.system(size: 20, weight: .semibold)) }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(shareHex: 0x1A1A1A)).frame(height: 1)
        }
        .disabled(isBusy)
    }

    private func action<Icon: View>(
        _ title: String,
        action: ShareSheetViewModel.CardAction,
        primary: Bool = false,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            perform(action)
        } label: {
            VStack(spacing: 6) {
                icon()
                    .foregroundStyle(primary ? .black : .white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(primary ? Color(shareHex: PresetAccent.lime.hex) : Color(shareHex: 0x1C1C1C)))
                Text(title)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
