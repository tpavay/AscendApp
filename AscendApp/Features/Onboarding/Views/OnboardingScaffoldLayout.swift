import SwiftUI

struct OnboardingScaffoldLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var horizontalPadding: CGFloat {
        min(max(size.width * 0.075, 26), 34)
    }

    var bottomPadding: CGFloat {
        safeAreaInsets.bottom + 18
    }

    var primaryButtonHeight: CGFloat {
        size.height < 740 ? 52 : 58
    }

    var topChromeHeight: CGFloat {
        OnboardingChromeMetrics.backButtonTopPadding + OnboardingChromeMetrics.backButtonSize
    }
}
