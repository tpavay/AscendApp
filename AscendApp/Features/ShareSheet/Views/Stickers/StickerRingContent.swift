import SwiftUI

/// The personal-record sticker: the climb's most significant record inside a ring.
struct StickerRingContent: View {
    private let effort: ShareSheetSubject.BestEffort
    let ink: StickerInk

    init?(subject: ShareSheetSubject, ink: StickerInk) {
        guard let effort = subject.bestEfforts.first else { return nil }
        self.effort = effort
        self.ink = ink
    }

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                ink.text(effort.rankText.uppercased(), size: 20, lineHeight: 1)
                ink.text(effort.scopeText.uppercased(), size: 6, trackingEm: 0.16, opacity: 0.85)
            }
            .frame(width: 62, height: 62)
            .overlay {
                Circle().strokeBorder(ink.color, lineWidth: 2)
            }
            ink.text(effort.title.uppercased(), size: 7, trackingEm: 0.14)
        }
    }
}
