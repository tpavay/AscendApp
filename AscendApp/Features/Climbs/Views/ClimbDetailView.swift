@preconcurrency import FirebaseAuth
import SwiftData
import SwiftUI

enum ClimbDetailOnboardingCoachMode {
    case firstClimb
}

private enum ClimbDetailCoachStep: Int, CaseIterable {
    case start
    case leaderboard
    case browse

    var title: String {
        switch self {
        case .start:
            return "Start here"
        case .leaderboard:
            return "Race the board"
        case .browse:
            return "Pick your next climb"
        }
    }

    var message: String {
        switch self {
        case .start:
            return "When you are on the stair stepper, tap the climb button to start the live attempt."
        case .leaderboard:
            return "The leaderboard shows completed times for this landmark. Finish the climb to put your name on it."
        case .browse:
            return "Use the globe button anytime to browse every landmark and choose another climb."
        }
    }

    var iconName: String {
        switch self {
        case .start:
            return "figure.stairs"
        case .leaderboard:
            return "list.number"
        case .browse:
            return "globe.americas.fill"
        }
    }

    var primaryActionTitle: String {
        self == .browse ? "DONE" : "NEXT"
    }

    var cardHeight: CGFloat {
        switch self {
        case .start:
            return 236
        case .leaderboard:
            return 250
        case .browse:
            return 230
        }
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .start:
            return 22
        case .leaderboard:
            return 24
        case .browse:
            return 26
        }
    }

    var spotlightPadding: CGFloat {
        switch self {
        case .start:
            return 6
        case .leaderboard:
            return 4
        case .browse:
            return 8
        }
    }

    var next: ClimbDetailCoachStep? {
        switch self {
        case .start:
            return .leaderboard
        case .leaderboard:
            return .browse
        case .browse:
            return nil
        }
    }
}

struct ClimbDetailView: View {
    let showsBrowseBackButton: Bool
    let analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint
    let onboardingCoach: ClimbDetailOnboardingCoachMode?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var viewModel: ClimbDetailViewModel
    @State private var selectedPage = 0
    @State private var detailPageHeights: [Int: CGFloat] = [:]
    @State private var showingBrowseClimbs = false
    @State private var showingFlyover = false
    @State private var showingLiveClimbSession = false
    @State private var selectedHistoryWorkout: Workout?
    @State private var showingHeadphoneHelp = false
    @State private var isHeroCardFlipped = false
    @State private var didTrackDetailViewed = false
    @State private var browseViewModel = GlobeViewModel()
    @State private var headphoneMotionService = HeadphoneMotionReadinessService.shared
    @State private var actionErrorMessage: String?
    @State private var didStartOnboardingCoach = false
    @State private var activeCoachStep: ClimbDetailCoachStep?
    @State private var coachTargetFrames: [ClimbDetailCoachStep: CGRect] = [:]

    init(
        climb: Climb,
        showsBrowseBackButton: Bool = false,
        analyticsEntryPoint: LiveClimbAnalyticsEvent.EntryPoint = .unknown,
        onboardingCoach: ClimbDetailOnboardingCoachMode? = nil
    ) {
        self.showsBrowseBackButton = showsBrowseBackButton
        self.analyticsEntryPoint = analyticsEntryPoint
        self.onboardingCoach = onboardingCoach
        _viewModel = State(initialValue: ClimbDetailViewModel(climb: climb))
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private static let detailPageTitles = [
        "OVERVIEW",
        "HISTORY",
        "LEADERBOARD"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard
                detailPageSelector
                detailPages
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsBrowseBackButton)
        .toolbar {
            if showsBrowseBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    OnboardingBackButton {
                        dismiss()
                    }
                    .accessibilityLabel("Back to Globe")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFlyover = true
                } label: {
                    Image(systemName: "airplane")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.78))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Flyover")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentBrowseFromDetail()
                } label: {
                    AppIcon(token: .globeHemisphereWest, pointSize: 23)
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.78))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(coachTargetFrameReader(for: .browse))
                .overlay {
                    coachTargetCircleHighlight(for: .browse)
                }
                .accessibilityLabel("Browse climbs")
            }
        }
        .fullScreenCover(isPresented: $showingFlyover) {
            ClimbFlyoverScreen(climb: viewModel.climb)
        }
        .navigationDestination(item: $selectedHistoryWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .navigationDestination(isPresented: $showingBrowseClimbs) {
            ClimbBrowseView(viewModel: browseViewModel, analyticsEntryPoint: .detailBrowse)
        }
        .navigationDestination(isPresented: $showingLiveClimbSession) {
            LiveClimbSessionView(
                climb: viewModel.climb,
                analyticsEntryPoint: analyticsEntryPoint
            )
        }
        .sheet(isPresented: $showingHeadphoneHelp) {
            liveClimbHeadphoneHelpSheet
                .appSheetStyle(.fitted())
        }
        .alert("Climb Action Error", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "Something went wrong.")
        }
        .overlay {
            if let activeCoachStep {
                GeometryReader { proxy in
                    climbDetailCoachOverlay(step: activeCoachStep, proxy: proxy)
                }
                .ignoresSafeArea()
            }
        }
        .task {
            trackDetailViewedIfNeeded()
            headphoneMotionService.refresh()
            viewModel.refresh(modelContext: modelContext)
            await viewModel.refreshLeaderboardSummary(modelContext: modelContext)
            startOnboardingCoachIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            headphoneMotionService.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
            Task {
                await viewModel.refreshLeaderboardSummary(modelContext: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            viewModel.refresh(modelContext: modelContext)
            Task {
                await viewModel.refreshLeaderboardSummary(modelContext: modelContext)
            }
        }
    }

    private func startOnboardingCoachIfNeeded() {
        guard onboardingCoach == .firstClimb, !didStartOnboardingCoach else { return }

        didStartOnboardingCoach = true
        selectedPage = 0
        withAnimation(.easeInOut(duration: 0.22)) {
            activeCoachStep = .start
        }
    }

    private func climbDetailCoachOverlay(step: ClimbDetailCoachStep, proxy: GeometryProxy) -> some View {
        let targetFrame = localCoachTargetFrame(for: step, in: proxy)
        let spotlightFrame = coachSpotlightFrame(for: step, targetFrame: targetFrame, containerSize: proxy.size)
        let cardWidth = min(proxy.size.width - 36, 366)
        let cardPosition = coachCardPosition(
            for: step,
            targetFrame: targetFrame,
            containerSize: proxy.size,
            cardSize: CGSize(width: cardWidth, height: step.cardHeight)
        )

        return ZStack(alignment: .topLeading) {
            ClimbDetailCoachScrim(
                spotlightFrame: spotlightFrame,
                cornerRadius: step.spotlightCornerRadius
            )
            .fill(Color.black.opacity(0.64), style: FillStyle(eoFill: true))
            .ignoresSafeArea()

            if let spotlightFrame {
                RoundedRectangle(cornerRadius: step.spotlightCornerRadius, style: .continuous)
                    .stroke(Color.accent.opacity(0.95), lineWidth: 2)
                    .shadow(color: Color.accent.opacity(0.52), radius: 16, x: 0, y: 0)
                    .frame(width: spotlightFrame.width, height: spotlightFrame.height)
                    .position(x: spotlightFrame.midX, y: spotlightFrame.midY)
                    .allowsHitTesting(false)
            }

            climbDetailCoachCard(step: step)
                .frame(width: cardWidth, height: step.cardHeight, alignment: .topLeading)
                .position(cardPosition)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
        }
        .animation(.easeInOut(duration: 0.22), value: step)
    }

    private func climbDetailCoachCard(step: ClimbDetailCoachStep) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: step.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.accent))

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("\(step.rawValue + 1) of \(ClimbDetailCoachStep.allCases.count)")
                        .font(.montserratSemiBold(size: 11))
                        .tracking(1.1)
                        .foregroundStyle(Color.accent)
                }

                Spacer(minLength: 0)
            }

            Text(step.message)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(action: finishCoach) {
                    Text("Skip")
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)

                Button(action: advanceCoach) {
                    Text(step.primaryActionTitle)
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "151515"))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 14)
    }

    private func localCoachTargetFrame(for step: ClimbDetailCoachStep, in proxy: GeometryProxy) -> CGRect? {
        guard let frame = coachTargetFrames[step],
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return nil
        }

        let rootFrame = proxy.frame(in: .global)
        return frame.offsetBy(dx: -rootFrame.minX, dy: -rootFrame.minY)
    }

    private func coachSpotlightFrame(
        for step: ClimbDetailCoachStep,
        targetFrame: CGRect?,
        containerSize: CGSize
    ) -> CGRect? {
        guard let targetFrame else { return nil }

        let paddedFrame = targetFrame.insetBy(dx: -step.spotlightPadding, dy: -step.spotlightPadding)
        let visibleBounds = CGRect(origin: .zero, size: containerSize)
        guard paddedFrame.intersects(visibleBounds) else { return nil }

        return paddedFrame
    }

    private func coachCardPosition(
        for step: ClimbDetailCoachStep,
        targetFrame: CGRect?,
        containerSize: CGSize,
        cardSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 18
        let gap: CGFloat = 18
        let x = containerSize.width / 2
        let fallbackY = containerSize.height - margin - cardSize.height / 2
        guard let targetFrame else {
            return CGPoint(x: x, y: fallbackY)
        }

        let bottomSpace = containerSize.height - targetFrame.maxY - margin
        let topSpace = targetFrame.minY - margin
        let minY = margin + cardSize.height / 2
        let maxY = containerSize.height - margin - cardSize.height / 2

        if bottomSpace >= cardSize.height + gap || bottomSpace >= topSpace {
            let proposedY = targetFrame.maxY + gap + cardSize.height / 2
            return CGPoint(x: x, y: min(max(proposedY, minY), maxY))
        }

        let proposedY = targetFrame.minY - gap - cardSize.height / 2
        return CGPoint(x: x, y: min(max(proposedY, minY), maxY))
    }

    private func coachTargetFrameReader(for step: ClimbDetailCoachStep) -> some View {
        ClimbDetailCoachTargetFrameReader { frame in
            updateCoachTargetFrame(frame, for: step)
        }
    }

    @ViewBuilder
    private func coachTargetRoundedHighlight(
        for step: ClimbDetailCoachStep,
        cornerRadius: CGFloat
    ) -> some View {
        if activeCoachStep == step {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.accent.opacity(0.96), lineWidth: 2.5)
                .shadow(color: Color.accent.opacity(0.62), radius: 13, x: 0, y: 0)
                .padding(-5)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func coachTargetCircleHighlight(for step: ClimbDetailCoachStep) -> some View {
        if activeCoachStep == step {
            Circle()
                .stroke(Color.accent.opacity(0.96), lineWidth: 2.5)
                .shadow(color: Color.accent.opacity(0.62), radius: 13, x: 0, y: 0)
                .padding(-5)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func updateCoachTargetFrame(_ frame: CGRect, for step: ClimbDetailCoachStep) {
        guard frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else { return }

        guard coachTargetFrames[step] != frame else { return }

        DispatchQueue.main.async {
            coachTargetFrames[step] = frame
        }
    }

    private func advanceCoach() {
        guard let activeCoachStep else { return }

        guard let next = activeCoachStep.next else {
            finishCoach()
            return
        }

        if next == .leaderboard {
            selectedPage = 2
        } else if next == .browse {
            selectedPage = 0
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            self.activeCoachStep = next
        }
    }

    private func finishCoach() {
        withAnimation(.easeInOut(duration: 0.18)) {
            activeCoachStep = nil
        }
    }

    private var heroCard: some View {
        let heroShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return ZStack {
            heroCardFace {
                heroCardFront
            }
                .opacity(isHeroCardFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(isHeroCardFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )

            heroCardFace {
                heroCardBack
            }
                .opacity(isHeroCardFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(isHeroCardFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )

            if !isHeroCardFlipped {
                flipCardButton
                    .transition(.opacity)
            }
        }
        .contentShape(heroShape)
        .onTapGesture {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                isHeroCardFlipped.toggle()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Flip the climb card")
    }

    private func heroCardFace<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let heroShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return content()
            .frame(maxWidth: .infinity)
            .frame(height: 390)
            .clipShape(heroShape)
            .animatedClimbCardBorder(
                colors: viewModel.climb.tier.borderColors,
                shadowColor: viewModel.climb.tier.shadowColor,
                cornerRadius: 28,
                lineWidth: 1.8,
                isEmphasized: viewModel.climb.tier.usesEmphasizedBorderStyle,
                animationStyle: .full
            )
    }

    private var heroCardFront: some View {
        ZStack(alignment: .bottomLeading) {
            ClimbArtworkView(climb: viewModel.climb, variant: .hero)

            LinearGradient(
                colors: [
                    .black.opacity(0.03),
                    .black.opacity(0.1),
                    .black.opacity(0.22),
                    .black.opacity(0.52)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let stripOrderText = viewModel.stripOrderText {
                HStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 28,
                            bottomLeading: 28,
                            bottomTrailing: 0,
                            topTrailing: 0
                        ),
                        style: .continuous
                    )
                        .fill(viewModel.climb.tier.detailStripStyle)
                        .frame(width: 48)
                        .overlay {
                            Text(stripOrderText)
                                .font(.montserratBold(size: 13))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(-90))
                                .lineLimit(1)
                        }

                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.18),
                        .black.opacity(0.68),
                        .black.opacity(0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 132)
            }

            heroTextOverlay
        }
    }

    private var heroCardBack: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.96),
                    viewModel.climb.tier.color.opacity(0.18),
                    Color.black.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(viewModel.climb.tier.displayName) Tier")
                                .font(.montserratBold(size: 34))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Text(viewModel.climb.tier.stepRangeDescription)
                                .font(.montserratSemiBold(size: 14))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }

                    Spacer()
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 10) {
                    Text("LANDMARK FACT")
                        .font(.montserratSemiBold(size: 12))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.48))

                    Text(viewModel.climb.funFact)
                        .font(.montserratRegular(size: 17))
                        .foregroundStyle(.white)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(height: 1)
                }

                Text("Tap to flip back")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(24)
        }
    }

    private var heroTextOverlay: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(viewModel.climb.name)
                .font(.montserratBold(size: 18))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(viewModel.subtitle)
                .font(.montserratMedium(size: 12))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .shadow(color: .black.opacity(0.55), radius: 16, x: 0, y: 4)
        .padding(.leading, viewModel.stripOrderText == nil ? 20 : 64)
        .padding(.trailing, 16)
        .padding(.bottom, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var flipCardButton: some View {
        Button {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                isHeroCardFlipped.toggle()
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.58), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.36), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isHeroCardFlipped ? "Show climb artwork" : "Show climb details")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(16)
    }

    private var detailPageSelector: some View {
        HStack(spacing: 4) {
            ForEach(Self.detailPageTitles.indices, id: \.self) { index in
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        selectedPage = index
                    }
                } label: {
                    Text(Self.detailPageTitles[index])
                        .font(.montserratBold(size: 11))
                        .tracking(1.1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(index == selectedPage ? .black : selectorInactiveTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if index == selectedPage {
                                Capsule(style: .continuous)
                                    .fill(viewModel.climb.tier.color)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .background {
                    if index == 2 {
                        coachTargetFrameReader(for: .leaderboard)
                    }
                }
                .overlay {
                    if index == 2 {
                        coachTargetRoundedHighlight(for: .leaderboard, cornerRadius: 22)
                    }
                }
                .accessibilityLabel(Self.detailPageTitles[index].capitalized)
                .accessibilityValue(index == selectedPage ? "Selected" : "")
            }
        }
        .padding(4)
        .background(selectorBackgroundColor, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(selectorStrokeColor, lineWidth: 1)
        }
        .animation(.smooth(duration: 0.25), value: selectedPage)
    }

    private var selectorInactiveTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.64) : .black.opacity(0.56)
    }

    private var selectorBackgroundColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.045)
    }

    private var selectorStrokeColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08)
    }

    private var detailPages: some View {
        ZStack(alignment: .topLeading) {
            selectedDetailPageMeasurer

            TabView(selection: $selectedPage) {
                ForEach(0..<3, id: \.self) { pageIndex in
                    detailPageContent(for: pageIndex)
                        .tag(pageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: detailPageHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .onPreferenceChange(ClimbDetailPageHeightPreferenceKey.self) { heights in
            detailPageHeights.merge(heights) { _, newValue in newValue }
        }
        .animation(.smooth(duration: 0.25), value: detailPageHeight)
    }

    private var selectedDetailPageMeasurer: some View {
        detailPageContent(for: selectedPage)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ClimbDetailPageHeightPreferenceKey.self,
                        value: [selectedPage: geometry.size.height]
                    )
                }
            )
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var detailPageHeight: CGFloat {
        detailPageHeights[selectedPage] ?? detailPageHeights.values.max() ?? 320
    }

    @ViewBuilder
    private func detailPageContent(for pageIndex: Int) -> some View {
        switch pageIndex {
        case 0:
            overviewPage
        case 1:
            historyPage
        case 2:
            leaderboardPage
        default:
            EmptyView()
        }
    }

    private var historyMetrics: [HistoryMetric] {
        var metrics = [
            HistoryMetric(
                id: "completions",
                value: viewModel.historySummary.completionsCount.formatted(),
                label: "COMPLETIONS"
            ),
            HistoryMetric(
                id: "attempts",
                value: viewModel.historySummary.attemptsCount.formatted(),
                label: "ATTEMPTS"
            )
        ]

        if let bestCompletionDurationSeconds = viewModel.historySummary.bestCompletionDurationSeconds {
            metrics.append(HistoryMetric(
                id: "best",
                value: DurationFormatter.format(duration: TimeInterval(bestCompletionDurationSeconds)),
                label: "BEST TIME"
            ))
        }

        if let averageCompletionDurationSeconds = viewModel.historySummary.averageCompletionDurationSeconds {
            metrics.append(HistoryMetric(
                id: "average",
                value: DurationFormatter.format(duration: TimeInterval(averageCompletionDurationSeconds)),
                label: "AVG TIME"
            ))
        }

        return metrics
    }

    private var historyMetricColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 72), spacing: 14),
            count: min(historyMetrics.count, 4)
        )
    }

    private var historyMetricsGrid: some View {
        LazyVGrid(columns: historyMetricColumns, alignment: .leading, spacing: 14) {
            ForEach(historyMetrics) { metric in
                historyMetric(value: metric.value, label: metric.label)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedPage)
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                metricCell(value: viewModel.climb.referenceStepCount.formatted(), title: "STEPS")
                metricDivider
                metricCell(value: viewModel.climb.calculatedFloors.formatted(), title: "FLOORS")
                metricDivider
                metricCell(value: viewModel.estimatedTimeText, title: "EST. TIME")
            }
            .frame(height: 58, alignment: .top)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            if viewModel.showsCommunityStats {
                communityStatsRow
            }

            primaryActionRow
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var historyPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            if viewModel.historySummary.recentEntries.isEmpty {
                Text("Attempts and completions for this climb will show up here.")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62))
            } else {
                historyMetricsGrid
                    .padding(.vertical, 2)

                Text("RECENT ATTEMPTS")
                    .font(.montserratSemiBold(size: 12))
                    .tracking(1.2)
                    .foregroundStyle(Color.customGray)

                VStack(spacing: 0) {
                    ForEach(viewModel.historySummary.recentEntries) { entry in
                        Button {
                            if let workout = workout(forAttemptId: entry.attemptId) {
                                selectedHistoryWorkout = workout
                            }
                        } label: {
                            historyRow(for: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, -2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var leaderboardPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if viewModel.completionLeaderboardCompletedCount > 0 {
                Text("\(viewModel.completionLeaderboardCompletedCount.formatted()) completed")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.accent)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let firstAscent = viewModel.leaderboardSummary.firstAscent {
                firstAscentSummary(firstAscent)
            }

            if viewModel.shouldShowPersonalRankSummary {
                personalLeaderboardRankSummary
            }

            if viewModel.isLeaderboardLoading && !viewModel.hasCompletionLeaderboardRows {
                leaderboardLoadingState
            } else if viewModel.hasCompletionLeaderboardRows {
                VStack(spacing: 8) {
                    ForEach(viewModel.completionLeaderboardRows) { row in
                        leaderboardRow(for: row)
                            .onAppear {
                                viewModel.loadMoreCompletionLeaderboardIfNeeded(currentRow: row)
                            }
                    }

                    if viewModel.isLoadingMoreCompletionRows {
                        leaderboardLoadingMoreState
                    }
                }
            } else if !viewModel.shouldShowPersonalRankSummary {
                leaderboardEmptyState
            }

            if viewModel.leaderboardErrorMessage != nil,
               !viewModel.isLeaderboardLoading {
                Text("Leaderboard unavailable")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color.red.opacity(0.82))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func firstAscentSummary(_ firstAscent: LiveReplayFirstAscent) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "flag.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(leaderboardGold)

            Text("First Ascent: \(firstAscent.displayName) · \(firstAscentDateText(for: firstAscent.completedAt))")
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(leaderboardGold)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.top, -8)
        .accessibilityElement(children: .combine)
    }

    private var leaderboardLoadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.accent)

            Text("Loading leaderboard")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.64) : .black.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var leaderboardLoadingMoreState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.accent)

            Text("Loading more")
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
    }

    private var leaderboardEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No completed times yet.")
                .font(.montserratBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text("First Ascent open. The first finisher claims it forever.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.66) : .black.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var personalLeaderboardRankSummary: some View {
        if let personalFinisherOrder = viewModel.personalFinisherOrder,
           let bestCompletionDurationSeconds = viewModel.historySummary.bestCompletionDurationSeconds {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your best")
                        .font(.montserratSemiBold(size: 12))
                        .tracking(1.0)
                        .foregroundStyle(Color.customGray)

                    Text(DurationFormatter.format(duration: TimeInterval(bestCompletionDurationSeconds)))
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("#\(personalFinisherOrder.formatted())")
                        .font(.montserratBold(size: 20))
                        .foregroundStyle(.accent)
                        .monospacedDigit()

                    Text("of \(viewModel.communityCompletedCount.formatted())")
                        .font(.montserratSemiBold(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.5))
                        .monospacedDigit()
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accent.opacity(effectiveColorScheme == .dark ? 0.12 : 0.10))
            )
        }
    }

    private func leaderboardRow(for row: LiveReplayLeaderboardRow) -> some View {
        let rank = row.rank
        let isPodium = isPodiumRank(rank)
        let isFirst = rank == 1
        let rowAccent = leaderboardAccentColor(for: rank)

        return HStack(alignment: .center, spacing: isFirst ? 14 : 12) {
            leaderboardRankView(for: rank)

            leaderboardAvatar(
                for: row,
                size: isFirst ? 50 : 42,
                borderColor: isPodium ? rowAccent : nil
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(row.isCurrentUser ? "You" : row.displayName)
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(leaderboardPrimaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if row.isCurrentUser {
                        Text("YOU")
                            .font(.montserratBold(size: 9))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accent)
                            )
                    }
                }

                Text("\(row.finalSteps.formatted()) steps")
                    .font(.montserratMedium(size: isFirst ? 12 : 11))
                    .foregroundStyle(leaderboardSecondaryTextColor)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(leaderboardDurationText(for: row))
                    .font(.montserratBold(size: isFirst ? 18 : 16))
                    .foregroundStyle(isPodium ? rowAccent : (row.isCurrentUser ? .accent : leaderboardPrimaryTextColor))
                    .monospacedDigit()

                if let averageStepsPerMinute = row.averageStepsPerMinute {
                    Text("\(Int(averageStepsPerMinute.rounded()).formatted()) avg SPM")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(leaderboardSecondaryTextColor)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, isFirst ? 16 : 13)
        .padding(.horizontal, isPodium || row.isCurrentUser ? 12 : 0)
        .background { leaderboardRowBackground(for: row) }
        .overlay(alignment: .bottom) {
            if !isPodium && !row.isCurrentUser {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .shadow(
            color: isFirst ? rowAccent.opacity(effectiveColorScheme == .dark ? 0.22 : 0.12) : .clear,
            radius: isFirst ? 12 : 0,
            x: 0,
            y: isFirst ? 4 : 0
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func leaderboardRankView(for rank: Int?) -> some View {
        if rank == 1 {
            Image(systemName: "crown.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(leaderboardGold)
                .frame(width: 34, alignment: .leading)
                .accessibilityLabel("Rank 1")
        } else {
            Text("#\(rank?.formatted() ?? "--")")
                .font(.montserratBold(size: 15))
                .foregroundStyle(leaderboardAccentColor(for: rank))
                .frame(width: 34, alignment: .leading)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func leaderboardRowBackground(for row: LiveReplayLeaderboardRow) -> some View {
        let rank = row.rank
        let rowAccent = leaderboardAccentColor(for: rank)

        if rank == 1 {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            rowAccent.opacity(effectiveColorScheme == .dark ? 0.18 : 0.12),
                            rowAccent.opacity(effectiveColorScheme == .dark ? 0.07 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(rowAccent.opacity(0.72), lineWidth: 1.4)
                )
        } else if isPodiumRank(rank) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rowAccent.opacity(effectiveColorScheme == .dark ? 0.10 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(rowAccent.opacity(0.28), lineWidth: 1)
                )
        } else if row.isCurrentUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accent.opacity(effectiveColorScheme == .dark ? 0.12 : 0.10))
        }
    }

    private func leaderboardDurationText(for row: LiveReplayLeaderboardRow) -> String {
        guard let completionDurationSeconds = row.completionDurationSeconds else {
            return "--"
        }

        return DurationFormatter.format(duration: completionDurationSeconds)
    }

    @ViewBuilder
    private func leaderboardAvatar(
        for row: LiveReplayLeaderboardRow,
        size: CGFloat = 42,
        borderColor: Color? = nil
    ) -> some View {
        let resolvedBorderColor = borderColor ?? (row.isCurrentUser ? Color.accent : .white.opacity(0.14))

        if let photoURL = row.isCurrentUser ? (row.photoURL ?? currentUserPhotoURL) : row.photoURL {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    leaderboardAvatarToken(for: row, size: size, borderColor: resolvedBorderColor)
                @unknown default:
                    leaderboardAvatarToken(for: row, size: size, borderColor: resolvedBorderColor)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(resolvedBorderColor, lineWidth: row.isCurrentUser || borderColor != nil ? 2 : 1)
            )
            .id(photoURL)
        } else {
            leaderboardAvatarToken(for: row, size: size, borderColor: resolvedBorderColor)
        }
    }

    private func leaderboardAvatarToken(
        for row: LiveReplayLeaderboardRow,
        size: CGFloat = 42,
        borderColor: Color? = nil
    ) -> some View {
        Text(row.isCurrentUser ? currentUserAvatar.token : row.avatarToken)
            .font(.montserratBold(size: 13))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(row.isCurrentUser ? Color.accent : communityAvatarColor(for: row.id))
            )
            .overlay(
                Circle()
                    .stroke(borderColor ?? (row.isCurrentUser ? Color.accent.opacity(0.7) : .white.opacity(0.14)), lineWidth: borderColor == nil ? 1 : 2)
            )
    }

    private func isPodiumRank(_ rank: Int?) -> Bool {
        guard let rank else { return false }
        return (1...3).contains(rank)
    }

    private func leaderboardAccentColor(for rank: Int?) -> Color {
        switch rank {
        case 1:
            return leaderboardGold
        case 2:
            return Color(hex: "BFC4CC")
        case 3:
            return Color(hex: "C8793D")
        default:
            return Color.customGray
        }
    }

    private var leaderboardGold: Color {
        Color(hex: "F3D76B")
    }

    private var leaderboardPrimaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var leaderboardSecondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48)
    }

    private func firstAscentDateText(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    private func metricCell(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.montserratBold(size: 20))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text(title)
                .font(.montserratSemiBold(size: 12))
                .tracking(1.0)
                .foregroundStyle(Color.customGray)
        }
        .frame(maxWidth: .infinity)
    }

    private var communityStatsRow: some View {
        HStack(alignment: .center, spacing: 14) {
            communityAvatarStack
                .layoutPriority(1)

            communityCaption
                .layoutPriority(2)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(communityAccessibilityLabel)
    }

    @ViewBuilder
    private var communityAvatarStack: some View {
        if !visibleCommunityAvatars.isEmpty {
            HStack(spacing: -10) {
                ForEach(visibleCommunityAvatars) { avatar in
                    ClimbCommunityAvatarView(
                        avatar: avatar,
                        effectiveColorScheme: effectiveColorScheme
                    )
                }
            }
            .frame(height: 44)
        }
    }

    private var communityCaption: some View {
        Group {
            if viewModel.communityCompletedCount == 0 {
                Text("First Ascent open. The first finisher claims it forever.")
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(communitySecondaryColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(viewModel.communityCompletedCount.formatted())
                        .font(.montserratBold(size: 17))
                        .foregroundStyle(.accent)
                        .monospacedDigit()

                    Text(" completed")
                        .font(.montserratRegular(size: 17))
                        .foregroundStyle(communitySecondaryColor)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
        }
    }

    private var communityAccessibilityLabel: String {
        if viewModel.communityCompletedCount == 0 {
            return "First Ascent open. The first finisher claims it forever."
        }
        return "\(viewModel.communityCompletedCount) completed"
    }

    private var visibleCommunityAvatars: [ClimbCommunityAvatar] {
        guard viewModel.communityCompletedCount > 0 else { return [] }

        let currentState = currentUserCommunityState
        let remoteLimit = currentState == nil ? 3 : 2
        let currentToken = currentUserAvatar.token
        let currentDisplayName = currentUserDisplayName
        let currentUserId = Auth.auth().currentUser?.uid
        var avatars: [ClimbCommunityAvatar] = []

        if let currentState {
            avatars.append(currentUserAvatar(style: currentState))
        }

        let remoteAvatars = completedCommunityRows
            .filter { row in
                guard currentState != nil else { return true }
                if let currentUserId, row.userId == currentUserId {
                    return false
                }
                let displayNamesMatch = !currentDisplayName.isEmpty &&
                    row.displayName.compare(currentDisplayName, options: .caseInsensitive) == .orderedSame
                return row.avatarToken != currentToken && !displayNamesMatch
            }
            .prefix(remoteLimit)
            .map(communityAvatar)

        avatars.append(contentsOf: remoteAvatars)
        return Array(avatars.prefix(3))
    }

    private var currentUserCommunityState: ClimbCommunityAvatar.Style? {
        if viewModel.hasCompletionHistory {
            return .currentCompleted
        }

        return nil
    }

    private var completedCommunityRows: [LiveReplayLeaderboardRow] {
        let rows = viewModel.completionLeaderboardRows.isEmpty
            ? viewModel.leaderboardPreviewRows
            : viewModel.completionLeaderboardRows
        var seenKeys: Set<String> = []
        var uniqueRows: [LiveReplayLeaderboardRow] = []

        for row in rows {
            let key = communityIdentityKey(for: row)
            guard seenKeys.insert(key).inserted else { continue }
            uniqueRows.append(row)
        }

        return uniqueRows
    }

    private func communityIdentityKey(for row: LiveReplayLeaderboardRow) -> String {
        if let userId = row.userId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userId.isEmpty {
            return "user:\(userId)"
        }

        if let photoURL = row.photoURL?.absoluteString,
           !photoURL.isEmpty {
            return "photo:\(photoURL)"
        }

        return [
            row.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            row.avatarToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: "|")
    }

    private var currentUserAvatar: ClimbCommunityAvatar {
        currentUserAvatar(style: .regular)
    }

    private func currentUserAvatar(style: ClimbCommunityAvatar.Style) -> ClimbCommunityAvatar {
        ClimbCommunityAvatar(
            id: "current-user",
            token: Self.avatarToken(for: currentUserDisplayName),
            photoURL: currentUserPhotoURL,
            backgroundColor: Color(red: 0.22, green: 0.72, blue: 0.68),
            style: style
        )
    }

    private var currentUserDisplayName: String {
        let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedDisplayName, !cachedDisplayName.isEmpty {
            return cachedDisplayName
        }

        let authDisplayName = Auth.auth().currentUser?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let authDisplayName, !authDisplayName.isEmpty {
            return authDisplayName
        }

        return "You"
    }

    private var currentUserPhotoURL: URL? {
        if let cachedURL = UserDataRepository.shared.getCachedProfilePictureURL()
            .flatMap(URL.init(string:)) {
            return cachedURL
        }

        return Auth.auth().currentUser?.photoURL
    }

    private func communityAvatar(for row: LiveReplayLeaderboardRow) -> ClimbCommunityAvatar {
        ClimbCommunityAvatar(
            id: row.id,
            token: row.avatarToken,
            photoURL: row.photoURL,
            backgroundColor: communityAvatarColor(for: row.id),
            style: .regular
        )
    }

    private func communityAvatarColor(for id: String) -> Color {
        let colors: [Color] = [
            Color(red: 0.94, green: 0.33, blue: 0.43),
            Color(red: 0.21, green: 0.72, blue: 0.69),
            Color(red: 1.0, green: 0.57, blue: 0.08),
            Color(red: 0.40, green: 0.34, blue: 0.86)
        ]
        return colors[Int(id.hashValue.magnitude % UInt(colors.count))]
    }

    private var communityPrimaryColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var communitySecondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.62) : .black.opacity(0.58)
    }

    private static func avatarToken(for displayName: String) -> String {
        let token = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()

        return token.isEmpty ? "YOU" : token
    }

    private func historyMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.montserratBold(size: 24))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.montserratSemiBold(size: 10))
                .tracking(1.0)
                .foregroundStyle(Color.customGray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Finds the workout backing a climb attempt so a history tap can open it.
    private func workout(forAttemptId attemptId: UUID) -> Workout? {
        let attemptKey = attemptId.uuidString
        let climbAttemptRaw = WorkoutParticipationContextType.climbAttempt.rawValue
        let descriptor = FetchDescriptor<WorkoutParticipation>(
            predicate: #Predicate { participation in
                participation.contextId == attemptKey && participation.contextTypeRawValue == climbAttemptRaw
            }
        )
        return (try? modelContext.fetch(descriptor))?.first?.workout
    }

    private func historyRow(for entry: ClimbHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.montserratSemiBold(size: 15))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text(historyRowSubtitle(for: entry))
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.5))
            }

            Spacer(minLength: 0)

            if entry.status == .failed {
                historyBadge(
                    title: "ATTEMPT",
                    foreground: .white.opacity(0.72),
                    background: .white.opacity(0.08)
                )
            } else if entry.isPersonalBest {
                historyBadge(
                    title: "PR",
                    foreground: Color(hex: "F3E58A"),
                    background: Color(hex: "F3E58A").opacity(0.14)
                )
            }

            Text(DurationFormatter.format(duration: TimeInterval(entry.durationSeconds)))
                .font(.montserratBold(size: 17))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .monospacedDigit()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func historyBadge(title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.montserratSemiBold(size: 11))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
    }

    private func historyRowSubtitle(for entry: ClimbHistoryEntry) -> String {
        switch entry.status {
        case .completed:
            return "\(entry.totalSteps.formatted()) steps"
        case .failed:
            return "\(entry.recordedSteps.formatted()) / \(entry.totalSteps.formatted()) steps"
        case .active, .abandoned:
            return "\(entry.recordedSteps.formatted()) steps"
        }
    }

    private func secondaryActionButton(
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.montserratSemiBold(size: 15))
                .foregroundStyle(role == .destructive ? Color.red.opacity(0.86) : .white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
    }

    private var primaryActionRow: some View {
        HStack(spacing: 10) {
            Button(action: handlePrimaryAction) {
                Text(primaryActionTitle)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(isPrimaryActionEnabled ? .black : .white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isPrimaryActionEnabled ? Color.accent : .white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isPrimaryActionEnabled)
            .background(coachTargetFrameReader(for: .start))
            .overlay {
                coachTargetRoundedHighlight(for: .start, cornerRadius: 22)
            }

            Button {
                showingHeadphoneHelp = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.68))
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Live climb headphone help")
        }
    }

    private var primaryActionTitle: String {
        viewModel.actionTitle
    }

    private var isPrimaryActionEnabled: Bool {
        viewModel.isActionEnabled
    }

    private var liveClimbHeadphoneHelpSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Compatible Headphones")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                Text("Ascend uses headphone motion to track steps in real time during Live Climbs.")
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            compatibleHeadphoneGroup(
                title: "AirPods",
                headphones: [
                    "AirPods 3",
                    "AirPods 4",
                    "AirPods 4 with Active Noise Cancellation",
                    "AirPods Pro 1",
                    "AirPods Pro 2",
                    "AirPods Pro 3",
                    "AirPods Max"
                ]
            )

            compatibleHeadphoneGroup(
                title: "Beats",
                headphones: [
                    "Beats Fit Pro",
                    "Beats Studio Pro",
                    "Beats Solo 4",
                    "Powerbeats Pro 2",
                    "Powerbeats Fit"
                ]
            )

            Link(destination: Self.appleHeadphoneCompatibilityURL) {
                Text("Don't see yours? Check Apple's current list.")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 10)
        .appSheetBackground()
    }

    private func compatibleHeadphoneGroup(title: String, headphones: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.montserratSemiBold(size: 11))
                .tracking(1.1)
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.48))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(headphones, id: \.self) { headphone in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(.accent)
                            .frame(width: 5, height: 5)

                        Text(headphone)
                            .font(.montserratRegular(size: 13))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.76) : .black.opacity(0.66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
        }
    }

    private static let appleHeadphoneCompatibilityURL = URL(string: "https://support.apple.com/en-us/102596")!

    private func handlePrimaryAction() {
        let canStart = headphoneMotionService.readiness.canStartLiveClimb
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.detailStartTapped(
                climb: viewModel.climb,
                entryPoint: analyticsEntryPoint,
                actionState: startActionState,
                canStart: canStart
            )
        )

        guard headphoneMotionService.readiness.canStartLiveClimb else {
            TelemetryManager.shared.track(
                LiveClimbAnalyticsEvent.detailStartBlocked(
                    climb: viewModel.climb,
                    entryPoint: analyticsEntryPoint,
                    reason: .headphonesUnavailable
                )
            )
            actionErrorMessage = "Connect compatible headphones to start this live climb."
            return
        }

        guard viewModel.isActionEnabled else { return }

        showingLiveClimbSession = true
    }

    private var startActionState: LiveClimbAnalyticsEvent.StartActionState {
        guard viewModel.isActionEnabled else { return .disabled }
        return .newAttempt
    }

    private func presentBrowseFromDetail() {
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.detailBrowseTapped(climb: viewModel.climb)
        )
        browseViewModel.prepareForBrowseEntry()
        showingBrowseClimbs = true
    }

    private func trackDetailViewedIfNeeded() {
        guard !didTrackDetailViewed else { return }
        didTrackDetailViewed = true
        TelemetryManager.shared.track(
            LiveClimbAnalyticsEvent.detailViewed(
                climb: viewModel.climb,
                entryPoint: analyticsEntryPoint
            )
        )
    }

}

private struct ClimbDetailCoachTargetFrameReader: View {
    let onChange: (CGRect) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    onChange(proxy.frame(in: .global))
                }
                .onChange(of: proxy.frame(in: .global)) { _, frame in
                    onChange(frame)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ClimbDetailCoachScrim: Shape {
    let spotlightFrame: CGRect?
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)

        if let spotlightFrame {
            path.addRoundedRect(
                in: spotlightFrame,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
        }

        return path
    }
}

private struct ClimbCommunityAvatar: Identifiable {
    enum Style {
        case regular
        case currentCompleted
    }

    let id: String
    let token: String
    let photoURL: URL?
    let backgroundColor: Color
    let style: Style
}

private struct HistoryMetric: Identifiable {
    let id: String
    let value: String
    let label: String
}

private struct ClimbDetailPageHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, newValue in newValue }
    }
}

private struct ClimbCommunityAvatarView: View {
    let avatar: ClimbCommunityAvatar
    let effectiveColorScheme: ColorScheme

    var body: some View {
        avatarContent
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay {
                borderOverlay
            }
            .shadow(
                color: glowColor,
                radius: glowRadius,
                x: 0,
                y: 0
            )
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let photoURL = avatar.photoURL {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    tokenContent
                @unknown default:
                    tokenContent
                }
            }
        } else {
            tokenContent
        }
    }

    private var tokenContent: some View {
        Text(avatar.token)
            .font(.montserratBold(size: 13))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Circle().fill(avatar.backgroundColor))
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch avatar.style {
        case .regular:
            Circle()
                .stroke(effectiveColorScheme == .dark ? .black.opacity(0.3) : .white.opacity(0.8), lineWidth: 2)
        case .currentCompleted:
            Circle()
                .stroke(Color.accent, lineWidth: 2.5)
                .padding(1.5)
        }
    }

    private var glowColor: Color {
        switch avatar.style {
        case .currentCompleted:
            return Color.accent.opacity(0.48)
        case .regular:
            return .clear
        }
    }

    private var glowRadius: CGFloat {
        switch avatar.style {
        case .currentCompleted:
            return 6
        case .regular:
            return 0
        }
    }
}

#Preview("Default") {
    NavigationStack {
        ClimbDetailView(climb: .preview, showsBrowseBackButton: true)
    }
    .preferredColorScheme(.dark)
}
