import SwiftUI

struct OnboardingScaffold<Background: View, Content: View, BottomContent: View>: View {
    var backAction: (() -> Void)?
    var isBackEnabled = true

    @ViewBuilder let background: () -> Background
    @ViewBuilder let content: (OnboardingScaffoldLayout) -> Content
    @ViewBuilder let bottomContent: (OnboardingScaffoldLayout) -> BottomContent

    var body: some View {
        GeometryReader { geometry in
            let layout = OnboardingScaffoldLayout(
                size: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets
            )

            ZStack(alignment: .topLeading) {
                background()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                content(layout)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                bottomContent(layout)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.bottom, layout.bottomPadding)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)

                if let backAction {
                    OnboardingBackButton(isEnabled: isBackEnabled, action: backAction)
                        .padding(.leading, OnboardingChromeMetrics.backButtonLeadingPadding)
                        .padding(.top, OnboardingChromeMetrics.backButtonTopPadding)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

extension OnboardingScaffold where BottomContent == EmptyView {
    init(
        backAction: (() -> Void)? = nil,
        isBackEnabled: Bool = true,
        @ViewBuilder background: @escaping () -> Background,
        @ViewBuilder content: @escaping (OnboardingScaffoldLayout) -> Content
    ) {
        self.backAction = backAction
        self.isBackEnabled = isBackEnabled
        self.background = background
        self.content = content
        self.bottomContent = { _ in EmptyView() }
    }
}
