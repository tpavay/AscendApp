import SwiftUI

/// The rounded accent border the text-only seasonal stickers sit in. The border colour is the
/// theme's accent, so it stays the same when the climber changes the sticker Color.
struct SeasonalStickerFrame<Inner: View>: View {
    let accent: Color
    private let inner: Inner

    init(accent: Color, @ViewBuilder inner: () -> Inner) {
        self.accent = accent
        self.inner = inner()
    }

    var body: some View {
        inner
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 2)
            }
    }
}
