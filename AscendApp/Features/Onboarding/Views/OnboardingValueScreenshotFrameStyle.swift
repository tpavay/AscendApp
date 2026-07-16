import SwiftUI

struct OnboardingValueScreenshotFrameStyle {
    var width: CGFloat
    var height: CGFloat
    var topCrop: CGFloat
    var sourceAspectRatio: CGFloat
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var borderOpacity: Double
    var shadowRadius: CGFloat
    var shadowYOffset: CGFloat
    var shadowOpacity: Double

    static var onboarding: OnboardingValueScreenshotFrameStyle {
        tuning
    }

    static let tuning = OnboardingValueScreenshotFrameStyle(
        width: 300,
        height: 650,
        topCrop: 30,
        sourceAspectRatio: 2622.0 / 1206.0,
        cornerRadius: 24,
        borderWidth: 1.25,
        borderOpacity: 0.32,
        shadowRadius: 18,
        shadowYOffset: 14,
        shadowOpacity: 0.34
    )
}
