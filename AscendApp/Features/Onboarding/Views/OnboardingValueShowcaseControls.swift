import SwiftUI

struct OnboardingValueShowcaseControls: View {
    let activePageIndex: Int
    let pageCount: Int
    let buttonTitle: String
    let buttonHeight: CGFloat
    var controlGap: CGFloat = 10
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingValueShowcaseCarouselDots(
                activeIndex: activePageIndex,
                totalCount: pageCount
            )

            OnboardingValueShowcaseButton(
                title: buttonTitle,
                height: buttonHeight,
                action: onContinue
            )
            .padding(.top, controlGap)
        }
    }
}
