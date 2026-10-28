import SwiftUI

/// A picture behind the card with the bottom scrim that keeps the headline readable on it.
struct PresetImageBackground: View {
    /// Black at the bottom, easing off toward the top, as in the approved mockup.
    enum Scrim {
        case tower
        case photo

        /// Stops from the top of the card to the bottom.
        var stops: [Gradient.Stop] {
            switch self {
            case .tower:
                return [
                    .init(color: .black.opacity(0.15), location: 0),
                    .init(color: .black.opacity(0.3), location: 0.5),
                    .init(color: .black.opacity(0.85), location: 1)
                ]
            case .photo:
                return [
                    .init(color: .black.opacity(0.2), location: 0),
                    .init(color: .black.opacity(0.35), location: 0.55),
                    .init(color: .black.opacity(0.82), location: 1)
                ]
            }
        }
    }

    let image: UIImage
    let focalY: CGFloat
    let scrim: Scrim

    var body: some View {
        ZStack {
            PresetFilledImage(image: image, focalY: focalY)
            LinearGradient(stops: scrim.stops, startPoint: .top, endPoint: .bottom)
        }
    }
}
