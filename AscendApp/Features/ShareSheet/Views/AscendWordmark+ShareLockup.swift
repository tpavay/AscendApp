import SwiftUI

extension AscendWordmark.Treatment {
    /// The treatment closest to the two colours a share palette asks for.
    ///
    /// A lime A beside white or black letters is exactly the brand artwork. The artwork cannot draw
    /// an A in any other colour, so a different A takes the letters' colour and the lockup goes mono.
    static func shareLockup(letters: ShareColor, mark: ShareColor) -> Self {
        switch (letters, mark) {
        case (.paper, ShareColor(PresetAccent.lime.hex)): .onDark
        case (.ink, ShareColor(PresetAccent.lime.hex)): .onLight
        default: .mono(Color(share: letters))
        }
    }
}
