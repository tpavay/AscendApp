import SwiftUI

/// Minimal: one line in the bottom-left corner.
struct PresetMinimalLayout: View {
    let model: PresetCardModel

    var body: some View {
        Text(Self.unbreakable(model.minimalLine))
            .presetText(model.font, size: 15, weight: 800, trackingEm: -0.01, color: Color(share: model.palette.foreground))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    /// The line may break between one stat and the next, never inside one: `#806 of 914` keeps its
    /// spaces non-breaking, so a figure is never split from its unit. The dot stays with the stat
    /// before it, so a wrapped line ends on a dot and never begins with one.
    static func unbreakable(_ line: String) -> String {
        line.components(separatedBy: " · ")
            .map { $0.replacing(" ", with: "\u{00A0}") }
            .joined(separator: "\u{00A0}· ")
    }
}
