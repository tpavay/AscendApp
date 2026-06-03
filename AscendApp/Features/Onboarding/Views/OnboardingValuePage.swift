import SwiftUI

struct OnboardingValuePage: Identifiable {
    enum Background {
        case image(
            String,
            dimmingOpacity: Double = 0.24,
            topReadabilityOpacity: Double = 0.55
        )
        case ambient(OnboardingValueAmbientBackground.Style)
        case solid(Color)
    }

    enum HeroPresentation {
        /// Hero asset rendered inside a phone-mockup frame (rounded corners, border, shadow).
        case framedScreenshot
        /// Hero asset is a full-composition image rendered edge-to-edge with no framing.
        case fullBleed
    }

    let id: String
    let headline: String
    let subtitle: String
    let heroImageName: String
    let background: Background
    let heroPresentation: HeroPresentation
    var heroScale: CGFloat
    var heroXOffset: CGFloat
    var heroYOffset: CGFloat
    var heroRotation: Angle

    init(
        id: String,
        headline: String,
        subtitle: String,
        heroImageName: String,
        background: Background,
        heroPresentation: HeroPresentation = .framedScreenshot,
        heroScale: CGFloat = 1,
        heroXOffset: CGFloat = 0,
        heroYOffset: CGFloat = 0,
        heroRotation: Angle = .degrees(-1.5)
    ) {
        self.id = id
        self.headline = headline
        self.subtitle = subtitle
        self.heroImageName = heroImageName
        self.background = background
        self.heroPresentation = heroPresentation
        self.heroScale = heroScale
        self.heroXOffset = heroXOffset
        self.heroYOffset = heroYOffset
        self.heroRotation = heroRotation
    }
}
