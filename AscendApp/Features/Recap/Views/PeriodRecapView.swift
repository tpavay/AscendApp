import SwiftUI

/// Where the climber goes when the recap closes.
enum PeriodRecapExit: Equatable {
    case close
    /// To the board that awarded the crown - "Take the crown", "Defend it".
    case openBoard(LeaderboardTimeFrame)
    /// To Home, where every climb starts.
    case startClimb
}

/// The recap story: full screen, a page at a time, each page advancing on its own or on a
/// tap. The pages and their order come from `PeriodRecapStoryBuilder`; this view only
/// shows them.
struct PeriodRecapView: View {
    let story: PeriodRecapStory
    let viewerId: String?
    let onExit: (PeriodRecapExit) -> Void
    /// Holds every page at rest with no auto-advance - for evidence renders.
    var isStatic = false

    @State private var pageIndex: Int
    @State private var pageProgress: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var showsPastChampions = false

    init(
        story: PeriodRecapStory,
        viewerId: String?,
        initialPage: Int = 0,
        isStatic: Bool = false,
        onExit: @escaping (PeriodRecapExit) -> Void
    ) {
        self.story = story
        self.viewerId = viewerId
        self.isStatic = isStatic
        self.onExit = onExit
        _pageIndex = State(initialValue: min(max(initialPage, 0), max(story.pages.count - 1, 0)))
    }

    private var page: PeriodRecapStory.Page {
        story.pages[pageIndex]
    }

    private var isLastPage: Bool {
        pageIndex == story.pages.count - 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background

                VStack(spacing: 0) {
                    progressBars
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    pageContent
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .contentShape(Rectangle())
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
                        .onTapGesture { location in
                            if location.x < contentWidth * 0.35 {
                                goBack()
                            } else {
                                advance()
                            }
                        }
                        .id(pageIndex)
                        .transition(.opacity)

                    callToAction
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
            .environment(\.recapIsStatic, isStatic)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsPastChampions) {
                PastChampionsView(timeFrame: pastChampionsTimeFrame)
            }
        }
        .preferredColorScheme(.dark)
        .trackOnce(screen: .periodRecap)
        .task(id: pageIndex) {
            await runPageTimer()
        }
        .accessibilityAction(named: "Previous page") { goBack() }
        .accessibilityAction(named: "Next page") { advance() }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var background: some View {
        if case .everyone(let summary) = page {
            PeriodRecapLandmarkBackground(period: summary.period)
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var progressBars: some View {
        if story.chapters.isEmpty {
            HStack(spacing: 4) {
                ForEach(story.pages.indices, id: \.self) { index in
                    bar(fill: index < pageIndex ? 1 : (index == pageIndex ? pageProgress : 0))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(pageIndex + 1) of \(story.pages.count)")
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(story.chapters.enumerated()), id: \.offset) { _, chapter in
                    VStack(alignment: .leading, spacing: 6) {
                        bar(fill: chapterFill(chapter))
                        Text(chapter.label)
                            .font(.montserratBold(size: 10))
                            .tracking(1.4)
                            .foregroundStyle(chapter.pageRange.contains(pageIndex) ? .white : .white.opacity(0.5))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chapterAccessibilityLabel)
        }
    }

    private var chapterAccessibilityLabel: String {
        let chapter = story.chapters.first { $0.pageRange.contains(pageIndex) }
        let page = "page \(pageIndex + 1) of \(story.pages.count)"
        guard let chapter else { return page.capitalized }
        return "\(chapter.label.capitalized), \(page)"
    }

    private func chapterFill(_ chapter: PeriodRecapStory.Chapter) -> CGFloat {
        if pageIndex >= chapter.pageRange.upperBound { return 1 }
        guard chapter.pageRange.contains(pageIndex) else { return 0 }
        let done = CGFloat(pageIndex - chapter.pageRange.lowerBound)
        return (done + pageProgress) / CGFloat(chapter.pageRange.count)
    }

    private func bar(fill: CGFloat) -> some View {
        Capsule()
            .fill(.white.opacity(0.22))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * min(max(fill, 0), 1))
                }
            }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(headerLabel.text)
                .font(.montserratBold(size: 11))
                .tracking(2.2)
                .foregroundStyle(headerLabel.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            Button {
                onExit(.close)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close recap")
        }
        .frame(height: 44)
    }

    private var headerLabel: (text: String, color: Color) {
        switch page {
        case .everyone(let summary):
            return (PeriodRecapCopy.periodLabel(for: summary.period), periodColor(summary.period))
        case .yours(let summary):
            return (PeriodRecapCopy.periodLabel(for: summary.period), periodColor(summary.period))
        case .noClimbs(let summary):
            return (PeriodRecapCopy.periodLabel(for: summary.period), periodColor(summary.period))
        case .crown(let crown):
            return ("\(ChampionTitleLine.periodName(for: crown.period)) · THE CROWN", crown.title.tint)
        case .crowns:
            return ("THE CROWNS", Color.championGold)
        case .catchUp:
            return ("WHILE YOU WERE AWAY", Color.accent)
        }
    }

    private func periodColor(_ period: LeaderboardPeriod) -> Color {
        period.timeFrame == .monthly ? Color.championDiamond : Color.accent
    }

    // MARK: - Pages

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .everyone(let summary):
            PeriodRecapEveryonePage(summary: summary)
        case .yours(let summary):
            PeriodRecapYourPage(summary: summary)
        case .noClimbs(let summary):
            PeriodRecapNoClimbsPage(summary: summary, viewerId: viewerId)
        case .crown(let crown):
            PeriodRecapCrownPage(
                crown: crown,
                viewerId: viewerId,
                isFirstClimbInvitation: story.isFirstClimbInvitation
            )
        case .crowns(let crowns):
            PeriodRecapCrownsPage(crowns: crowns, viewerId: viewerId)
        case .catchUp(let catchUp):
            PeriodRecapCatchUpPage(catchUp: catchUp, viewerId: viewerId)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var callToAction: some View {
        if !isLastPage {
            RecapCallToAction(title: "NEXT: \(nextPageName) ›") { advance() }
        } else {
            let final = finalAction
            RecapCallToAction(
                title: final.title,
                secondaryTitle: final.showsPastChampions ? "PAST CHAMPIONS" : nil,
                action: { onExit(final.exit) },
                secondaryAction: final.showsPastChampions ? { showsPastChampions = true } : nil
            )
        }
    }

    private var nextPageName: String {
        guard pageIndex + 1 < story.pages.count else { return "" }
        switch story.pages[pageIndex + 1] {
        case .everyone(let summary):
            return ChampionTitleLine.periodName(for: summary.period)
        case .yours(let summary):
            return PeriodRecapCopy.yourSectionLabel(for: summary.period)
        case .noClimbs(let summary):
            return ChampionTitleLine.periodName(for: summary.period)
        case .crown:
            return "THE CROWN"
        case .crowns:
            return "THE CROWNS"
        case .catchUp:
            return "CATCH UP"
        }
    }

    private var finalAction: (title: String, exit: PeriodRecapExit, showsPastChampions: Bool) {
        switch page {
        case .crown(let crown):
            if crown.viewerIsChampion {
                return ("DEFEND IT", .openBoard(crown.period.timeFrame), true)
            }
            if story.isFirstClimbInvitation {
                return ("START YOUR FIRST CLIMB", .startClimb, false)
            }
            return ("TAKE THE CROWN", .openBoard(crown.period.timeFrame), true)
        case .crowns:
            return ("CLIMB THIS WEEK", .openBoard(.weekly), true)
        case .catchUp:
            return ("CLIMB TODAY", .startClimb, true)
        case .noClimbs:
            return ("START A CLIMB", .startClimb, false)
        case .everyone, .yours:
            return story.isFirstClimbInvitation
                ? ("START YOUR FIRST CLIMB", .startClimb, false)
                : ("CLIMB THIS WEEK", .openBoard(.weekly), false)
        }
    }

    private var pastChampionsTimeFrame: LeaderboardTimeFrame {
        switch page {
        case .crown(let crown): crown.period.timeFrame
        default: .weekly
        }
    }

    private func advance() {
        guard !isLastPage else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            pageIndex += 1
        }
    }

    private func goBack() {
        guard pageIndex > 0 else {
            pageProgress = 0
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            pageIndex -= 1
        }
    }

    /// Fills the page's bar and moves on when it is full. The last page waits for the
    /// climber, and nothing advances while past champions covers the story.
    private func runPageTimer() async {
        guard !isStatic else {
            pageProgress = isLastPage ? 1 : 0
            return
        }
        pageProgress = 0
        let duration = Self.duration(for: page)
        // Let the empty bar render before it fills, or the fill animates from full to full.
        try? await Task.sleep(for: .milliseconds(40))
        withAnimation(.linear(duration: duration)) {
            pageProgress = 1
        }
        guard !isLastPage else { return }
        do {
            try await Task.sleep(for: .seconds(duration))
        } catch {
            return
        }
        guard !showsPastChampions else { return }
        advance()
    }

    static func duration(for page: PeriodRecapStory.Page) -> TimeInterval {
        switch page {
        case .everyone: 5
        case .yours: 9
        case .noClimbs, .catchUp: 8
        case .crown, .crowns: 6
        }
    }
}
