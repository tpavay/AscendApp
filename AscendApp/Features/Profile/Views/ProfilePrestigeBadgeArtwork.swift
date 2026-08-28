import SwiftUI

/// A badge's free-standing cut-out art, in one of two states.
///
/// Earned art carries the tint as a glow. Unearned art is a ghost: greyscale, barely there, and
/// still occupying its slot - a blank half of a row reads as a rendering failure, whereas a
/// ghost reads as something not won yet. Nothing here clips or frames the artwork; a rounded
/// tile would slice it and a stroke would draw an edge around transparency.
///
/// This is deliberately the single home for the ghost, so the queued own-profile locked-ladder
/// idea can adopt it rather than inventing a second visual language for "not earned yet".
struct ProfilePrestigeBadgeArtwork: View {
    let asset: String
    let tint: Color
    let size: CGFloat
    var isEarned = true

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .grayscale(isEarned ? 0 : 1)
            .opacity(isEarned ? 1 : 0.22)
            .shadow(color: tint.opacity(isEarned ? 0.26 : 0), radius: 6, y: 2)
    }
}
