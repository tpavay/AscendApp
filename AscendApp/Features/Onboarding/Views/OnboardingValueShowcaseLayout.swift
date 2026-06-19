import SwiftUI

struct OnboardingValueShowcaseLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var horizontalPadding: CGFloat {
        min(max(size.width * 0.07, 24), 34)
    }

    var upperBackgroundHeight: CGFloat {
        bottomPanelSolidTop
    }

    var topBackgroundBleed: CGFloat {
        max(safeAreaInsets.top, 56)
    }

    var bottomPanelSolidTop: CGFloat {
        max(textSectionTop - 12, size.height * 0.58)
    }

    var bottomPanelSolidHeight: CGFloat {
        size.height - bottomPanelSolidTop
    }

    var bottomPanelBlendHeight: CGFloat {
        min(max(size.height * 0.085, 58), 78)
    }

    var screenshotStyle: OnboardingValueScreenshotFrameStyle {
        let base = OnboardingValueScreenshotFrameStyle.onboarding
        let width = min(size.width * 0.61, base.width)
        let scale = width / base.width

        return OnboardingValueScreenshotFrameStyle(
            width: width,
            height: base.height * scale,
            topCrop: base.topCrop * scale,
            sourceAspectRatio: base.sourceAspectRatio,
            cornerRadius: base.cornerRadius * scale,
            borderWidth: base.borderWidth,
            borderOpacity: base.borderOpacity,
            shadowRadius: base.shadowRadius,
            shadowYOffset: base.shadowYOffset,
            shadowOpacity: base.shadowOpacity
        )
    }

    var screenshotTopPadding: CGFloat {
        max(safeAreaInsets.top + 22, 68)
    }

    var screenshotHeight: CGFloat {
        screenshotStyle.height
    }

    var textSectionHeight: CGFloat {
        size.height < 740 ? 138 : 150
    }

    var textSectionTop: CGFloat {
        size.height - textSectionBottomPadding - textSectionHeight
    }

    var textSectionBottomPadding: CGFloat {
        bottomPadding + buttonHeight + 18 + 5 + textToControlsGap
    }

    var buttonHeight: CGFloat {
        size.height < 740 ? 52 : 56
    }

    var bottomPadding: CGFloat {
        max(safeAreaInsets.bottom, size.height * 34 / 844)
    }

    var textToControlsGap: CGFloat {
        size.height < 740 ? 14 : 16
    }

    var dotsToButtonGap: CGFloat {
        size.height < 740 ? 8 : 10
    }

    var heroBottomGap: CGFloat {
        size.height < 740 ? 24 : 32
    }

    var headlineSize: CGFloat {
        min(max(size.width * 0.077, 28), 30)
    }

    var subtitleSize: CGFloat {
        min(max(size.width * 0.037, 14), 15)
    }

    var textStackSpacing: CGFloat {
        10
    }
}
