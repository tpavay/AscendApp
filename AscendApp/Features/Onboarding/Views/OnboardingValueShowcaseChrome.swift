import SwiftUI

struct OnboardingValueShowcaseChrome: View {
    let activePageIndex: Int
    let pageCount: Int
    let buttonTitle: String
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / 390
            let scaleY = geometry.size.height / 844

            ZStack(alignment: .top) {
                OnboardingValueShowcaseControls(
                    activePageIndex: activePageIndex,
                    pageCount: pageCount,
                    buttonTitle: buttonTitle,
                    buttonHeight: 56 * scaleY,
                    controlGap: 22 * scaleY,
                    onContinue: onContinue
                )
                .frame(width: 334 * scaleX, height: 85 * scaleY, alignment: .top)
                .position(x: geometry.size.width / 2, y: (683 + 42.5) * scaleY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
