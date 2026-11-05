import SwiftUI

/// The pictures the selling screens draw: the welcome hero and the Mountain screenshot in 02's
/// phone. Both live in the asset catalogue; this is the one place that names them.
enum SellScreenAssets {
    /// Climbers heading up a stone staircase to a summit. Fills the top of 01.
    static let welcomeHero = "SellWelcomeHero"

    /// A Mountain climb as the build draws it, with no seasonal gear on the athletes, so the
    /// screenshot never dates itself to a month. Re-capture it when the Mountain's look changes.
    static let mountainScreenshot = "SellMountainScreenshot"
}

/// A picture that fills a frame without widening whatever it sits in: it is drawn as an overlay on
/// a view that takes exactly the proposal, because a filled image reports the size it scaled to,
/// not the size it was offered.
struct SellFilledImage: View {
    let name: String
    var scale: CGFloat = 1

    var body: some View {
        Color.clear
            .overlay {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale, anchor: .center)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
