import SwiftUI

struct OnboardingValueCarouselView: View {
    @Binding var selectedIndex: Int
    @State private var scrollPositionID: String?

    let pages: [OnboardingValuePage]
    let onFinish: () -> Void

    var body: some View {
        Group {
            if pages.isEmpty {
                Color.black
                    .ignoresSafeArea()
            } else {
                GeometryReader { geometry in
                    ZStack {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 0) {
                                ForEach(pages) { page in
                                    OnboardingValueShowcasePageContent(
                                        headline: page.headline,
                                        subtitle: page.subtitle,
                                        backgroundImageName: backgroundImageName(for: page),
                                        screenshotImageName: page.heroImageName
                                    )
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .id(page.id)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollIndicators(.hidden)
                        .scrollPosition(id: $scrollPositionID)
                        .scrollTargetBehavior(.paging)

                        OnboardingValueShowcaseChrome(
                            activePageIndex: selectedIndex,
                            pageCount: pages.count,
                            buttonTitle: buttonTitle(for: selectedIndex),
                            onContinue: continueFromCurrentPage
                        )
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .onAppear {
                    clampSelectedIndex()
                    syncScrollPositionToSelectedIndex()
                }
                .onChange(of: pages.count) { _, _ in
                    clampSelectedIndex()
                    syncScrollPositionToSelectedIndex()
                }
                .onChange(of: selectedIndex) { _, _ in
                    syncScrollPositionToSelectedIndex()
                }
                .onChange(of: scrollPositionID) { _, newID in
                    updateSelectedIndex(for: newID)
                }
            }
        }
        .background(Color.black)
    }

    private func backgroundImageName(for page: OnboardingValuePage) -> String {
        switch page.background {
        case .image(let imageName, _, _):
            imageName
        case .ambient:
            "OnboardingGlobalClimbsBackground"
        }
    }

    private func buttonTitle(for index: Int) -> String {
        index == pages.count - 1 ? "Get Started" : "Continue"
    }

    private func continueFromCurrentPage() {
        onFinish()
    }

    private func clampSelectedIndex() {
        guard !pages.isEmpty else {
            selectedIndex = 0
            return
        }

        selectedIndex = min(max(selectedIndex, 0), pages.count - 1)
    }

    private func syncScrollPositionToSelectedIndex() {
        guard pages.indices.contains(selectedIndex) else {
            scrollPositionID = nil
            return
        }

        let selectedPageID = pages[selectedIndex].id
        if scrollPositionID != selectedPageID {
            scrollPositionID = selectedPageID
        }
    }

    private func updateSelectedIndex(for pageID: String?) {
        guard let pageID,
              let index = pages.firstIndex(where: { $0.id == pageID }),
              selectedIndex != index else {
            return
        }

        selectedIndex = index
    }
}

#Preview("Onboarding Value Carousel") {
    OnboardingValueCarouselPreviewHost()
}

#Preview("Onboarding Tracking Page") {
    OnboardingValueTrackingPagePreviewHost()
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

private struct OnboardingValueTrackingPagePreviewHost: View {
    @State private var selectedIndex = 2

    var body: some View {
        OnboardingValueCarouselView(
            selectedIndex: $selectedIndex,
            pages: OnboardingValuePages.all,
            onFinish: {}
        )
    }
}
