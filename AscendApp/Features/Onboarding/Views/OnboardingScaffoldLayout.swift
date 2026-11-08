import SwiftUI

struct OnboardingScaffoldLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
    /// How far the bottom content ends above the frame's bottom edge, when a screen sets it. The
    /// default adds the home indicator's height, which is right for a scaffold that spans the safe
    /// area (the old flow's screens all do) and one inset too many for one laid out inside it.
    var fixedBottomPadding: CGFloat?

    var horizontalPadding: CGFloat {
        min(max(size.width * 0.075, 26), 34)
    }

    var bottomPadding: CGFloat {
        fixedBottomPadding ?? safeAreaInsets.bottom + 18
    }

    var primaryButtonHeight: CGFloat {
        size.height < 740 ? 52 : 58
    }

    var topChromeHeight: CGFloat {
        OnboardingChromeMetrics.backButtonTopPadding + OnboardingChromeMetrics.backButtonSize
    }
}
