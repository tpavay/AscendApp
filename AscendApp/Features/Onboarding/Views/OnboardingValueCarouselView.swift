import SwiftUI

struct OnboardingValueCarouselView: View {
    @Binding var selectedIndex: Int

    let pages: [OnboardingValuePage]
    let onFinish: () -> Void

    var body: some View {
        Group {
            if pages.isEmpty {
                Color.black
                    .ignoresSafeArea()
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        GeometryReader { pageGeometry in
                            let pageOffset = pageGeometry.frame(in: .global).minX

                            OnboardingValueScreen(
                                activePageIndex: index,
                                pageCount: pages.count,
                                headline: page.headline,
                                subtitle: page.subtitle,
                                buttonTitle: buttonTitle(for: index),
                                parallaxOffset: pageOffset * -0.06,
                                onContinue: continueFromCurrentPage,
                                background: {
                                    pageBackground(page)
                                },
                                hero: {
                                    OnboardingValuePhoneMockup(
                                        imageName: page.heroImageName,
                                        scale: page.heroScale,
                                        xOffset: page.heroXOffset,
                                        yOffset: page.heroYOffset,
                                        rotation: page.heroRotation
                                    )
                                }
                            )
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onAppear(perform: clampSelectedIndex)
                .onChange(of: pages.count) { _, _ in
                    clampSelectedIndex()
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: selectedIndex)
    }

    @ViewBuilder
    private func pageBackground(_ page: OnboardingValuePage) -> some View {
        switch page.background {
        case .image(let imageName):
            OnboardingValueImageBackground(imageName: imageName)
        case .ambient(let style):
            OnboardingValueAmbientBackground(style: style)
        }
    }

    private func buttonTitle(for index: Int) -> String {
        index == pages.count - 1 ? "Get Started" : "Continue"
    }

    private func continueFromCurrentPage() {
        if selectedIndex < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.32)) {
                selectedIndex += 1
            }
        } else {
            onFinish()
        }
    }

    private func clampSelectedIndex() {
        guard !pages.isEmpty else {
            selectedIndex = 0
            return
        }

        selectedIndex = min(max(selectedIndex, 0), pages.count - 1)
    }
}

#Preview("Onboarding Value Carousel") {
    OnboardingValueCarouselPreviewHost()
}

private struct OnboardingValueCarouselPreviewHost: View {
    @State private var selectedIndex = 0

    private let pages = OnboardingValuePages.all

    var body: some View {
        OnboardingValueCarouselView(
            selectedIndex: $selectedIndex,
            pages: pages,
            onFinish: {}
        )
    }
}
