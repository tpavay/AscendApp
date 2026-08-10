import SwiftUI

struct OnboardingValueCarouselView: View {
    static let defaultAnalyticsSegmentID = "pre_auth_value_onboarding"

    @Binding var selectedIndex: Int
    @State private var scrollPositionID: String?

    let pages: [OnboardingValuePage]
    var analyticsSegmentID = defaultAnalyticsSegmentID
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
            OnboardingLandmarksValuePageContent(subtitle: page.subtitle)
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

        recordCurrentPageCompleted(actionID: "continue")

        if selectedIndex < pages.count - 1 {
            selectedIndex += 1
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

        let previousIndex = selectedIndex
        if index > previousIndex {
            recordPageCompleted(
                at: previousIndex,
                inputType: "gesture",
                actionID: "swipe_forward"
            )
        } else if let context = Self.analyticsContext(
            segmentID: analyticsSegmentID,
            pages: pages,
            index: previousIndex
        ) {
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.backTapped(context: context, inputType: "gesture")
            )
        }

        selectedIndex = index
    }

    private func currentAnalyticsContext() -> OnboardingAnalyticsContext? {
        Self.analyticsContext(segmentID: analyticsSegmentID, pages: pages, index: selectedIndex)
    }

    private func recordCurrentPageCompleted(actionID: String) {
        recordPageCompleted(at: selectedIndex, inputType: "button", actionID: actionID)
    }

    private func recordPageCompleted(at index: Int, inputType: String, actionID: String) {
        guard let context = Self.analyticsContext(
            segmentID: analyticsSegmentID,
            pages: pages,
            index: index
        ) else { return }

        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.screenCompleted(
                context: context,
                inputType: inputType,
                properties: ["action_id": .string(actionID)]
            )
        )
    }

    /// Builds the context for a carousel page so surfaces that own chrome around the carousel
    /// (back buttons, scaffolds) report the same `step_id` the carousel itself reports.
    static func analyticsContext(
        segmentID: String = defaultAnalyticsSegmentID,
        pages: [OnboardingValuePage],
        index: Int
    ) -> OnboardingAnalyticsContext? {
        guard pages.indices.contains(index) else { return nil }

        return OnboardingAnalyticsContext(
            segmentID: segmentID,
            stepID: pages[index].id
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

    @MainActor
    private var pages: [OnboardingValuePage] { OnboardingValuePages.all }

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
