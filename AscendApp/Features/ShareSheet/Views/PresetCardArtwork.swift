import UIKit

/// The pictures a card may sit on, loaded before drawing so an exported card never captures an
/// async placeholder.
struct PresetCardArtwork {
    var tower: UIImage?
    var photo: UIImage?
    /// How the climber framed a chosen photo: a pinch scale (1 is fit) and a drag offset as a
    /// fraction of the card, so the screen preview and the 1080 export frame it the same way.
    var photoScale: CGFloat = 1
    var photoOffset: CGSize = .zero

    static let none = PresetCardArtwork()
}
