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

    struct FullBleedHeroFrame {
        let left: CGFloat
        let top: CGFloat
        let width: CGFloat
        let height: CGFloat

        static let progress = FullBleedHeroFrame(left: -37, top: -21, width: 464, height: 754)
        static let landmarks = FullBleedHeroFrame(left: -1, top: -95, width: 390, height: 729)
        static let `default` = FullBleedHeroFrame(left: 0, top: 0, width: 390, height: 580)
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
    var fullBleedHeroFrame: FullBleedHeroFrame

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
        heroRotation: Angle = .degrees(-1.5),
        fullBleedHeroFrame: FullBleedHeroFrame = .default
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
        self.fullBleedHeroFrame = fullBleedHeroFrame
    }
}
