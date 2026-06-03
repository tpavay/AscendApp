import SwiftUI

struct OnboardingValueCarouselView: View {
    @Binding var selectedIndex: Int
    @State private var scrollPositionID: String?
    @State private var didRecordFlowStart = false
    @State private var viewedPageIDs: Set<String> = []

    let pages: [OnboardingValuePage]
    var analyticsFlowID = "pre_auth_value_onboarding"
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
                                    ZStack {
                                        pageContent(for: page)
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                    }
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
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
                    recordFlowStartIfNeeded()
                    recordCurrentPageViewedIfNeeded()
                }
                .onChange(of: pages.count) { _, _ in
                    clampSelectedIndex()
                    syncScrollPositionToSelectedIndex()
                    recordCurrentPageViewedIfNeeded()
                }
                .onChange(of: selectedIndex) { _, _ in
                    syncScrollPositionToSelectedIndex()
                    recordCurrentPageViewedIfNeeded()
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
        case .ambient, .solid:
            "OnboardingGlobalClimbsBackground"
        }
    }

    @ViewBuilder
    private func pageContent(for page: OnboardingValuePage) -> some View {
        if page.id == "global-climbs" {
            OnboardingLandmarksValuePageContent(
                headline: page.headline,
                subtitle: page.subtitle
            )
        } else if page.id == "leaderboards" {
            OnboardingLeaderboardValuePageContent(
                headline: page.headline,
                subtitle: page.subtitle
            )
        } else {
            switch page.heroPresentation {
            case .fullBleed:
                OnboardingValueFullBleedPageContent(
                    headline: page.headline,
                    subtitle: page.subtitle,
                    heroImageName: page.heroImageName
                )
            case .framedScreenshot:
                OnboardingValueShowcasePageContent(
                    headline: page.headline,
                    subtitle: page.subtitle,
                    backgroundImageName: backgroundImageName(for: page),
                    screenshotImageName: page.heroImageName
                )
            }
        }
    }

    private func buttonTitle(for index: Int) -> String {
        index == pages.count - 1 ? "GET STARTED" : "CONTINUE"
    }

    private func continueFromCurrentPage() {
        guard !pages.isEmpty else {
            onFinish()
            return
        }

        let context = analyticsContext(for: pages[selectedIndex], index: selectedIndex)
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.stepCompleted(
                context: context,
                actionID: selectedIndex == pages.count - 1 ? "get_started" : "continue"
            )
        )

        if selectedIndex < pages.count - 1 {
            selectedIndex += 1
        } else {
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.flowCompleted(context: context)
            )
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

    private func recordFlowStartIfNeeded() {
        guard !didRecordFlowStart,
              pages.indices.contains(selectedIndex) else { return }

        didRecordFlowStart = true
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.flowStarted(
                context: analyticsContext(for: pages[selectedIndex], index: selectedIndex)
            )
        )
    }

    private func recordCurrentPageViewedIfNeeded() {
        guard pages.indices.contains(selectedIndex) else { return }

        let page = pages[selectedIndex]
        guard !viewedPageIDs.contains(page.id) else { return }

        viewedPageIDs.insert(page.id)
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.stepViewed(
                context: analyticsContext(for: page, index: selectedIndex)
            )
        )
    }

    private func analyticsContext(for page: OnboardingValuePage, index: Int) -> OnboardingAnalyticsContext {
        OnboardingAnalyticsContext(
            flowID: analyticsFlowID,
            stepID: page.id,
            stepIndex: index,
            stepCount: pages.count
        )
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
