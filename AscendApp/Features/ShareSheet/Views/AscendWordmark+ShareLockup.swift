import SwiftUI

extension AscendWordmark.Treatment {
    /// The treatment that draws the two colours a share palette asks for. A lime A beside white or
    /// black letters is exactly the brand artwork; anything else is tinted.
    static func shareLockup(letters: ShareColor, mark: ShareColor) -> Self {
        switch (letters, mark) {
        case (.paper, ShareColor(PresetAccent.lime.hex)): .onDark
        case (.ink, ShareColor(PresetAccent.lime.hex)): .onLight
        default: letters == mark
            ? .mono(Color(share: letters))
            : .twoColour(mark: Color(share: mark), letters: Color(share: letters))
        }
    }
}
