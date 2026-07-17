import SwiftUI

struct OnboardingValueCarouselView: View {
    static let defaultAnalyticsFlowID = "pre_auth_value_onboarding"

    @Binding var selectedIndex: Int
    @State private var scrollPositionID: String?
    @State private var didRecordFlowStart = false

    let pages: [OnboardingValuePage]
    var analyticsFlowID = defaultAnalyticsFlowID
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
                            buttonTitle: "CONTINUE",
                            onContinue: continueFromCurrentPage
                        )
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .onAppear {
                    clampSelectedIndex()
                    syncScrollPositionToSelectedIndex()
                    recordFlowStartIfNeeded()
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
                .trackOnboardingScreenView(currentAnalyticsContext())
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
                    heroImageName: page.heroImageName,
                    heroFrame: page.fullBleedHeroFrame
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

    private func continueFromCurrentPage() {
        guard !pages.isEmpty else {
            onFinish()
            return
        }

        if selectedIndex < pages.count - 1 {
            selectedIndex += 1
        } else {
            if let context = currentAnalyticsContext() {
                TelemetryManager.shared.track(
                    OnboardingAnalyticsEvent.flowCompleted(context: context)
                )
            }
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
              let context = currentAnalyticsContext() else { return }

        didRecordFlowStart = true
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.flowStarted(context: context)
        )
    }

    private func currentAnalyticsContext() -> OnboardingAnalyticsContext? {
        Self.analyticsContext(flowID: analyticsFlowID, pages: pages, index: selectedIndex)
    }

    /// Builds the context for a carousel page so surfaces that own chrome around the carousel
    /// (back buttons, scaffolds) report the same `step_id` the carousel itself reports.
    static func analyticsContext(
        flowID: String = defaultAnalyticsFlowID,
        pages: [OnboardingValuePage],
        index: Int
    ) -> OnboardingAnalyticsContext? {
        guard pages.indices.contains(index) else { return nil }

        return OnboardingAnalyticsContext(
            flowID: flowID,
            stepID: pages[index].id,
            stepIndex: index,
            stepCount: pages.count
        )
    }
}

#Preview("Onboarding Value Carousel") {
    OnboardingValueCarouselPreviewHost()
}

#Preview("Onboarding Landmark Page") {
    OnboardingValueLandmarkPagePreviewHost()
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

private struct OnboardingValueLandmarkPagePreviewHost: View {
    @State private var selectedIndex = 1

    var body: some View {
        OnboardingValueCarouselView(
            selectedIndex: $selectedIndex,
            pages: OnboardingValuePages.all,
            onFinish: {}
        )
    }
}
