import SwiftUI

struct OnboardingValuePage: Identifiable {
    enum Background {
        case image(String)
        case ambient(OnboardingValueAmbientBackground.Style)
    }

    let id: String
    let headline: String
    let subtitle: String
    let heroImageName: String
    let background: Background
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
        self.heroScale = heroScale
        self.heroXOffset = heroXOffset
        self.heroYOffset = heroYOffset
        self.heroRotation = heroRotation
    }
}
