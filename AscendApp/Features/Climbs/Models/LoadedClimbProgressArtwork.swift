import UIKit

/// A climb's progress cut-out with its image decoded and ready to draw.
struct LoadedClimbProgressArtwork: Equatable, Sendable {
    let artwork: ClimbProgressArtwork
    let image: UIImage

    /// The image is the artwork's own file at `artwork.path`, so two loads of the same path are
    /// the same cut-out.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.artwork == rhs.artwork
    }
}
