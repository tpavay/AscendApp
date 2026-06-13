import SwiftUI

struct PreAuthOnboardingValueCarouselScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    @State private var isShowingSignUp = false

    var body: some View {
        OnboardingScaffold(
            backAction: { dismiss() },
            background: {
                Color.black
            },
            content: { _ in
                OnboardingValueCarouselView(
                    selectedIndex: $selectedIndex,
                    pages: OnboardingValuePages.all,
                    onFinish: { isShowingSignUp = true }
                )
                .ignoresSafeArea()
            }
        )
        .navigationDestination(isPresented: $isShowingSignUp) {
            SignUpView()
        }
    }
}

private struct PreAuthOnboardingSurveyFlowScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    @State private var selectedAnswers: [String: Set<String>] = [:]
    @State private var didRecordFlowStart = false
    @State private var viewedQuestionIDs: Set<String> = []

    let onFinish: () -> Void

    private let questions = PreAuthSurveyQuestion.all

    var body: some View {
        PreAuthSurveyQuestionScreen(
            question: currentQuestion,
            selectedOptionIDs: selectedAnswers[currentQuestion.id, default: []],
            isContinueEnabled: !selectedAnswers[currentQuestion.id, default: []].isEmpty,
            onSelect: selectAnswer,
            onBack: handleBack,
            onContinue: moveForward
        )
        .background(PreAuthSurveyPalette.background)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            recordFlowStartIfNeeded()
            recordCurrentQuestionViewedIfNeeded()
        }
        .onChange(of: stepIndex) { _, _ in
            recordCurrentQuestionViewedIfNeeded()
        }
    }

    private var currentQuestion: PreAuthSurveyQuestion {
        questions[min(max(stepIndex, 0), questions.count - 1)]
    }

    private func handleBack() {
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.backTapped(context: analyticsContext(for: currentQuestion, index: stepIndex))
        )

        if stepIndex == 0 {
            dismiss()
        } else {
            stepIndex -= 1
        }
    }

    private func moveForward() {
        let question = currentQuestion
        let context = analyticsContext(for: question, index: stepIndex)
        recordSelectedAnswers(for: question, context: context)
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.stepCompleted(
                context: context,
                actionID: "continue"
            )
        )

        if stepIndex < questions.count - 1 {
            stepIndex += 1
        } else {
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.flowCompleted(context: context)
            )
            onFinish()
        }
    }

    private func selectAnswer(_ optionID: String) {
        var optionIDs = selectedAnswers[currentQuestion.id, default: []]

        switch currentQuestion.selectionMode {
        case .single:
            optionIDs = [optionID]
        case .multiple:
            if optionIDs.contains(optionID) {
                optionIDs.remove(optionID)
            } else {
                optionIDs.insert(optionID)
            }
        }

        selectedAnswers[currentQuestion.id] = optionIDs
        PreAuthOnboardingSurveyStore().save(questionID: currentQuestion.id, optionIDs: optionIDs)
    }

    private func recordFlowStartIfNeeded() {
        guard !didRecordFlowStart else { return }

        didRecordFlowStart = true
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.flowStarted(context: analyticsContext(for: currentQuestion, index: stepIndex))
        )
    }

    private func recordCurrentQuestionViewedIfNeeded() {
        let question = currentQuestion
        guard !viewedQuestionIDs.contains(question.id) else { return }

        viewedQuestionIDs.insert(question.id)
        let context = analyticsContext(for: question, index: stepIndex)
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.stepViewed(context: context)
        )
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.screenViewed(
                context: context,
                property: question.id
            )
        )
    }

    private func recordSelectedAnswers(
        for question: PreAuthSurveyQuestion,
        context: OnboardingAnalyticsContext
    ) {
        let selectedOptionIDs = selectedAnswers[question.id, default: []]
        for optionID in selectedOptionIDs.sorted() {
            let answerIndex = question.options.firstIndex { $0.id == optionID }
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.answerSelected(
                    context: context,
                    questionID: question.id,
                    answerID: optionID,
                    answerIndex: answerIndex
                )
            )
        }
    }

    private func analyticsContext(
        for question: PreAuthSurveyQuestion,
        index: Int
    ) -> OnboardingAnalyticsContext {
        OnboardingAnalyticsContext(
            flowID: "pre_auth_question_set_1",
            stepID: question.id,
            stepIndex: index,
            stepCount: questions.count
        )
    }
}

private struct PreAuthSurveyQuestionScreen: View {
    let question: PreAuthSurveyQuestion
    let selectedOptionIDs: Set<String>
    let isContinueEnabled: Bool
    let onSelect: (String) -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        PreAuthSurveyScreenShell(
            progressFraction: question.progressFraction,
            onBack: onBack,
            primaryTitle: "CONTINUE",
            isContinueEnabled: isContinueEnabled,
            onContinue: onContinue
        ) { metrics in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: metrics.height(5)) {
                    Text(question.eyebrow)
                        .font(.montserratSemiBold(size: metrics.font(11)))
                        .tracking(metrics.width(1.3))
                        .foregroundStyle(OnboardingValuePalette.lime)
                        .frame(width: metrics.width(334), height: metrics.height(16), alignment: .leading)

                    Text(question.headline)
                        .font(.montserratBold(size: metrics.font(28)))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(0)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: metrics.width(334), alignment: .topLeading)
                }
                .frame(width: metrics.width(334), alignment: .topLeading)
                .offset(x: metrics.x(28), y: metrics.y(154))

                ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                    PreAuthSurveyOptionRow(
                        title: option.title,
                        isSelected: selectedOptionIDs.contains(option.id),
                        metrics: metrics,
                        action: { onSelect(option.id) }
                    )
                    .frame(width: metrics.width(334), height: metrics.height(52))
                    .position(
                        x: metrics.x(195),
                        y: metrics.y(308 + CGFloat(index) * 66 + 26)
                    )
                }
            }
        }
    }
}

private struct PreAuthSurveyScreenShell<Content: View>: View {
    let progressFraction: CGFloat
    let onBack: () -> Void
    let primaryTitle: String
    let isContinueEnabled: Bool
    let onContinue: () -> Void
    @ViewBuilder let content: (PreAuthSurveyMetrics) -> Content

    var body: some View {
        GeometryReader { geometry in
            let metrics = PreAuthSurveyMetrics(size: geometry.size)

            ZStack(alignment: .topLeading) {
                PreAuthSurveyPalette.background
                    .ignoresSafeArea()

                OnboardingBackButton(action: onBack)
                    .position(
                        x: metrics.x(OnboardingChromeMetrics.backButtonLeadingPadding + OnboardingChromeMetrics.backButtonSize / 2),
                        y: metrics.y(OnboardingChromeMetrics.backButtonTopPadding + OnboardingChromeMetrics.backButtonSize / 2)
                    )

                PreAuthSurveyProgressBar(
                    progress: progressFraction
                )
                .frame(width: metrics.width(169), height: metrics.height(5))
                .position(x: metrics.x(195.5), y: metrics.y(75.5))

                content(metrics)

                Button(action: onContinue) {
                    Text(primaryTitle)
                        .font(.montserratBold(size: metrics.font(16)))
                        .foregroundStyle(.black.opacity(isContinueEnabled ? 0.9 : 0.45))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.radius(12), style: .continuous)
                                .fill(OnboardingValuePalette.lime.opacity(isContinueEnabled ? 1 : 0.45))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isContinueEnabled)
                .frame(width: metrics.width(334), height: metrics.height(56))
                .position(x: metrics.x(195), y: metrics.y(740))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct PreAuthSurveyProgressBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.2))

                Capsule(style: .continuous)
                    .fill(OnboardingValuePalette.lime)
                    .frame(width: geometry.size.width * clampedProgress)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("\(Int(clampedProgress * 100)) percent")
    }

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }
}

private struct PreAuthSurveyOptionRow: View {
    let title: String
    let isSelected: Bool
    let metrics: PreAuthSurveyMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.montserratSemiBold(size: metrics.font(14)))
                .foregroundStyle(.white.opacity(0.86))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.width(18))
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius(10), style: .continuous)
                        .fill(Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255).opacity(0.95))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.radius(10), style: .continuous)
                        .stroke(isSelected ? OnboardingValuePalette.lime.opacity(0.72) : .white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct PreAuthSurveyMetrics {
    let size: CGSize

    private var scaleX: CGFloat { size.width / 390 }
    private var scaleY: CGFloat { size.height / 844 }
    private var typeScale: CGFloat { min(scaleX, scaleY) }

    func x(_ value: CGFloat) -> CGFloat {
        value * scaleX
    }

    func y(_ value: CGFloat) -> CGFloat {
        value * scaleY
    }

    func width(_ value: CGFloat) -> CGFloat {
        value * scaleX
    }

    func height(_ value: CGFloat) -> CGFloat {
        value * scaleY
    }

    func font(_ value: CGFloat) -> CGFloat {
        value * typeScale
    }

    func radius(_ value: CGFloat) -> CGFloat {
        value * typeScale
    }
}

private enum PreAuthSurveyPalette {
    static let background = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
}

private struct PreAuthSurveyQuestion {
    enum SelectionMode {
        case single
        case multiple
    }

    let id: String
    let eyebrow: String
    let headline: String
    let headlineHeight: CGFloat
    let progressFraction: CGFloat
    let selectionMode: SelectionMode
    let options: [PreAuthSurveyOption]

    static let figmaProgressFraction = CGFloat(21.0 / 169.0)

    static let all: [PreAuthSurveyQuestion] = [
        PreAuthSurveyQuestion(
            id: "stair_stepper_baseline",
            eyebrow: "STAIR STEPPER BASELINE",
            headline: "How would you describe your stair stepper experience?",
            headlineHeight: 102,
            progressFraction: figmaProgressFraction,
            selectionMode: .single,
            options: [
                .init(id: "never_tried", title: "I’ve never tried it"),
                .init(id: "tried_a_few_times", title: "I’ve tried it a few times"),
                .init(id: "occasionally", title: "I use it occasionally"),
                .init(id: "all_the_time", title: "I use it all the time.")
            ]
        ),
        PreAuthSurveyQuestion(
            id: "exercise_level",
            eyebrow: "EXERCISE LEVEL",
            headline: "How often do you exercise?",
            headlineHeight: 68,
            progressFraction: figmaProgressFraction,
            selectionMode: .single,
            options: [
                .init(id: "new_to_regular_exercise", title: "I’m new to regular exercise"),
                .init(id: "one_two_per_week", title: "1-2 times per week"),
                .init(id: "three_four_per_week", title: "3-4 times per week"),
                .init(id: "five_plus_per_week", title: "5+ times per week")
            ]
        ),
        PreAuthSurveyQuestion(
            id: "goal",
            eyebrow: "GOAL",
            headline: "What brings you to the app?",
            headlineHeight: 68,
            progressFraction: figmaProgressFraction,
            selectionMode: .multiple,
            options: [
                .init(id: "lose_weight", title: "I want to lose weight"),
                .init(id: "build_endurance", title: "I want to build endurance"),
                .init(id: "track_progress", title: "I want to track my progress"),
                .init(id: "exciting_workouts", title: "I want more exciting workouts"),
                .init(id: "healthier_life", title: "I want to live a healthier life")
            ]
        ),
        PreAuthSurveyQuestion(
            id: "motivation",
            eyebrow: "MOTIVATION",
            headline: "What motivates you to workout?",
            headlineHeight: 68,
            progressFraction: figmaProgressFraction,
            selectionMode: .single,
            options: [
                .init(id: "specific_goal", title: "Working toward a specific goal"),
                .init(id: "competing_with_others", title: "Competing with others"),
                .init(id: "streak_alive", title: "Keeping my streak alive"),
                .init(id: "progress_over_time", title: "Seeing my progress over time")
            ]
        ),
        PreAuthSurveyQuestion(
            id: "plan",
            eyebrow: "YOUR PLAN",
            headline: "How often do you plan to use the stair stepper?",
            headlineHeight: 102,
            progressFraction: figmaProgressFraction,
            selectionMode: .single,
            options: [
                .init(id: "less_than_weekly", title: "Less than once per week"),
                .init(id: "one_two_per_week", title: "1-2 times per week"),
                .init(id: "three_four_per_week", title: "3-4 times per week"),
                .init(id: "five_plus_per_week", title: "5+ times per week")
            ]
        )
    ]
}

private struct PreAuthSurveyOption {
    let id: String
    let title: String
}

struct PreAuthOnboardingSurveyAnswers: Equatable {
    var stairStepperExperience: String?
    var exerciseLevel: String?

    var isEmpty: Bool {
        stairStepperExperience == nil && exerciseLevel == nil
    }
}

struct PreAuthOnboardingSurveyStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func answers() -> PreAuthOnboardingSurveyAnswers {
        PreAuthOnboardingSurveyAnswers(
            stairStepperExperience: firstAnswer(for: "stair_stepper_baseline"),
            exerciseLevel: firstAnswer(for: "exercise_level")
        )
    }

    func save(questionID: String, optionIDs: Set<String>) {
        let key = storageKey(for: questionID)

        if optionIDs.isEmpty {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(Array(optionIDs).sorted(), forKey: key)
        }
    }

    private func firstAnswer(for questionID: String) -> String? {
        userDefaults.stringArray(forKey: storageKey(for: questionID))?.first
    }

    private func storageKey(for questionID: String) -> String {
        "preAuthOnboardingSurvey.v1.\(questionID)"
    }
}

private struct PreAuthOnboardingGuideFlowScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    @State private var didRecordFlowStart = false
    @State private var viewedScreenIDs: Set<String> = []

    let onFinish: () -> Void

    private let screens = PreAuthGuideScreen.all

    var body: some View {
        PreAuthGuideScreenView(
            screen: currentScreen,
            onBack: handleBack,
            onContinue: moveForward
        )
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            recordFlowStartIfNeeded()
            recordCurrentScreenViewedIfNeeded()
        }
        .onChange(of: stepIndex) { _, _ in
            recordCurrentScreenViewedIfNeeded()
        }
    }

    private var currentScreen: PreAuthGuideScreen {
        screens[min(max(stepIndex, 0), screens.count - 1)]
    }

    private func handleBack() {
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.backTapped(context: analyticsContext(for: currentScreen, index: stepIndex))
        )

        if stepIndex == 0 {
            dismiss()
        } else {
            stepIndex -= 1
        }
    }

    private func moveForward() {
        let screen = currentScreen
        let context = analyticsContext(for: screen, index: stepIndex)
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.stepCompleted(
                context: context,
                actionID: "continue"
            )
        )

        if stepIndex < screens.count - 1 {
            stepIndex += 1
        } else {
            TelemetryManager.shared.track(
                OnboardingAnalyticsEvent.flowCompleted(context: context)
            )
            onFinish()
        }
    }

    private func recordFlowStartIfNeeded() {
        guard !didRecordFlowStart else { return }

        didRecordFlowStart = true
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.flowStarted(context: analyticsContext(for: currentScreen, index: stepIndex))
        )
    }

    private func recordCurrentScreenViewedIfNeeded() {
        let screen = currentScreen
        guard !viewedScreenIDs.contains(screen.id) else { return }

        viewedScreenIDs.insert(screen.id)
        let context = analyticsContext(for: screen, index: stepIndex)
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.stepViewed(context: context)
        )
        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.screenViewed(
                context: context,
                property: screen.id
            )
        )
    }

    private func analyticsContext(
        for screen: PreAuthGuideScreen,
        index: Int
    ) -> OnboardingAnalyticsContext {
        OnboardingAnalyticsContext(
            flowID: "pre_auth_guide",
            stepID: screen.id,
            stepIndex: index,
            stepCount: screens.count
        )
    }
}

private struct PreAuthGuideScreenView: View {
    let screen: PreAuthGuideScreen
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = PreAuthGuideMetrics(size: geometry.size)

            ZStack(alignment: .topLeading) {
                PreAuthSurveyPalette.background
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geometry.size.width, height: metrics.height(281))
                .position(x: geometry.size.width / 2, y: metrics.y(702.5))
                .allowsHitTesting(false)

                OnboardingBackButton(action: onBack)
                    .position(
                        x: metrics.x(OnboardingChromeMetrics.backButtonLeadingPadding + OnboardingChromeMetrics.backButtonSize / 2),
                        y: metrics.y(OnboardingChromeMetrics.backButtonTopPadding + OnboardingChromeMetrics.backButtonSize / 2)
                    )

                guideArtwork(metrics: metrics)

                VStack(spacing: metrics.height(11)) {
                    Text(screen.headline)
                        .font(.montserratBold(size: metrics.font(28)))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(0)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: metrics.width(340), alignment: .center)

                    Text(screen.subtitle)
                        .font(.montserratRegular(size: metrics.font(14)))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(metrics.height(2))
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: metrics.width(340), alignment: .center)
                }
                .frame(width: metrics.width(340), alignment: .top)
                .offset(x: metrics.x(25), y: metrics.y(543))

                Button(action: onContinue) {
                    Text("CONTINUE")
                        .font(.montserratBold(size: metrics.font(16)))
                        .foregroundStyle(.black.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.radius(12), style: .continuous)
                                .fill(OnboardingValuePalette.lime)
                        )
                }
                .buttonStyle(.plain)
                .frame(width: metrics.width(334), height: metrics.height(56))
                .position(x: metrics.x(195), y: metrics.y(740))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(PreAuthSurveyPalette.background)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func guideArtwork(metrics: PreAuthGuideMetrics) -> some View {
        switch screen.kind {
        case .landmarkCollage:
            PreAuthLandmarkCollage(metrics: metrics)
        case .liveTracking:
            PreAuthLiveClimbCard(metrics: metrics)
                .frame(width: metrics.width(236), height: metrics.height(396))
                .position(x: metrics.x(195), y: metrics.y(317))

            Image("OnboardingAirPodsCutout")
                .resizable()
                .scaledToFit()
                .frame(width: metrics.width(199), height: metrics.height(145))
                .position(x: metrics.x(294.5), y: metrics.y(464.5))
                .accessibilityHidden(true)
        case .dailyClimb:
            PreAuthDailyClimbLeaderboard(metrics: metrics)
                .frame(width: metrics.width(320), height: metrics.height(389), alignment: .top)
                .offset(x: metrics.x(36), y: metrics.y(110))
        }
    }
}

private struct PreAuthLandmarkCollage: View {
    let metrics: PreAuthGuideMetrics

    // Six bundled landmark assets fill seven Figma card slots; the repeat (Burj) hides in
    // the 29pt sliver bleeding off the top-left edge, diagonally opposite its full card.
    private static let topRowImages = [
        "OnboardingLandmarkBurjCard",
        "OnboardingLandmarkMachuCard",
        "OnboardingLandmarkEmpireCard",
        "OnboardingLandmarkEverestCard"
    ]

    private static let bottomRowImages = [
        "OnboardingLandmarkStatueCard",
        "OnboardingLandmarkEiffelCard",
        "OnboardingLandmarkBurjCard"
    ]

    var body: some View {
        ZStack {
            row(images: Self.topRowImages)
                .position(x: metrics.x(189.6), y: metrics.y(266.9))

            row(images: Self.bottomRowImages)
                .position(x: metrics.x(190.8), y: metrics.y(409.2))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(images: [String]) -> some View {
        HStack(spacing: metrics.width(10)) {
            ForEach(images.indices, id: \.self) { index in
                Image(images[index])
                    .resizable()
                    .scaledToFill()
                    .frame(width: metrics.width(146), height: metrics.height(146))
                    .clipShape(RoundedRectangle(cornerRadius: metrics.radius(24), style: .continuous))
            }
        }
        .rotationEffect(.degrees(3.5))
    }
}

private struct PreAuthLiveClimbCard: View {
    let metrics: PreAuthGuideMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.radius(15), style: .continuous)
                .fill(.white.opacity(0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.radius(15), style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                }

            VStack(spacing: metrics.height(2)) {
                Text("CURRENT CLIMB")
                    .font(.montserratBold(size: metrics.font(10)))
                    .tracking(metrics.width(1.3))
                    .foregroundStyle(OnboardingValuePalette.lime)

                Text("Empire State Building")
                    .font(.montserratBold(size: metrics.font(14)))
                    .foregroundStyle(.white)
            }
            .frame(width: metrics.width(236), height: metrics.height(50))

            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(width: metrics.width(236), height: 1)
                .offset(y: metrics.height(50))

            VStack(alignment: .leading, spacing: metrics.height(19)) {
                liveMetric(eyebrow: "ELAPSED", value: "24:18")
                liveMetric(eyebrow: "PROGRESS", value: "4,240", suffix: "/ 6800")
                liveMetric(eyebrow: "CADENCE", value: "65", suffix: "SPM ↑ PR PACE", suffixColor: OnboardingValuePalette.lime)
                liveMetric(eyebrow: "HEART RATE", value: "165", suffix: "BPM")
            }
            .offset(x: metrics.width(101), y: metrics.height(102))

            VStack(spacing: 0) {
                Text("SUMMIT\n6,800")
                    .font(.montserratBold(size: metrics.font(8)))
                    .foregroundStyle(Color(red: 148 / 255, green: 148 / 255, blue: 148 / 255))
                    .multilineTextAlignment(.center)
                    .lineSpacing(metrics.height(2))

                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color(red: 41 / 255, green: 41 / 255, blue: 41 / 255))
                        .frame(width: metrics.width(5), height: metrics.height(271))

                    Capsule()
                        .fill(OnboardingValuePalette.lime)
                        .frame(width: metrics.width(6), height: metrics.height(178))

                    Circle()
                        .fill(OnboardingValuePalette.lime)
                        .frame(width: metrics.width(10), height: metrics.height(10))
                        .shadow(color: OnboardingValuePalette.lime.opacity(0.95), radius: metrics.width(8), x: 0, y: 0)
                        .offset(y: -metrics.height(172))
                }
                .padding(.top, metrics.height(8))

                Text("START")
                    .font(.montserratBold(size: metrics.font(8)))
                    .foregroundStyle(Color(red: 98 / 255, green: 98 / 255, blue: 98 / 255))
            }
            .frame(width: metrics.width(48))
            .offset(x: metrics.width(18), y: metrics.height(65))

            Text("HALF")
                .font(.montserratBold(size: metrics.font(8)))
                .foregroundStyle(.white)
                .offset(x: metrics.width(45), y: metrics.height(226))
        }
    }

    private func liveMetric(
        eyebrow: String,
        value: String,
        suffix: String? = nil,
        suffixColor: Color = Color(red: 148 / 255, green: 148 / 255, blue: 148 / 255)
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.height(2)) {
            Text(eyebrow)
                .font(.montserratBold(size: metrics.font(8)))
                .tracking(metrics.width(0.69))
                .foregroundStyle(eyebrow == "ELAPSED" ? OnboardingValuePalette.lime : Color(red: 148 / 255, green: 148 / 255, blue: 148 / 255))

            HStack(alignment: .firstTextBaseline, spacing: metrics.width(2)) {
                Text(value)
                    .font(.montserratBold(size: metrics.font(24)))
                    .foregroundStyle(.white)

                if let suffix {
                    Text(suffix)
                        .font(.montserratBold(size: metrics.font(9.5)))
                        .foregroundStyle(suffixColor)
                }
            }
        }
    }
}

private struct PreAuthDailyClimbLeaderboard: View {
    let metrics: PreAuthGuideMetrics

    private let rows: [PreAuthLeaderboardRowData] = [
        .init(rank: "1", avatarName: "OnboardingLeaderboardAvatarFinn", name: "Finn R.", time: "1:24:23", isCurrentUser: false),
        .init(rank: "2", avatarName: "OnboardingLeaderboardAvatarRuby", name: "Ruby N.", time: "1:34:14", isCurrentUser: false),
        .init(rank: "3", avatarName: "OnboardingLeaderboardAvatarJack", name: "Jack L.", time: "1:43:32", isCurrentUser: false),
        .init(rank: "4", avatarName: "OnboardingLeaderboardAvatarYou", name: "You", time: "1:44:13", isCurrentUser: true),
        .init(rank: "5", avatarName: "OnboardingLeaderboardAvatarDustin", name: "Dustin F.", time: "1:49:16", isCurrentUser: false)
    ]

    var body: some View {
        VStack(spacing: metrics.height(18)) {
            VStack(spacing: metrics.height(5)) {
                Text("CLIMB OF THE DAY")
                    .font(.montserratBold(size: metrics.font(10)))
                    .tracking(metrics.width(1.3))
                    .foregroundStyle(OnboardingValuePalette.lime)

                Text("MOUNT FUJI")
                    .font(.montserratBold(size: metrics.font(14)))
                    .foregroundStyle(.white)
            }
            .frame(height: metrics.height(34))

            VStack(spacing: metrics.height(10)) {
                ForEach(rows) { row in
                    PreAuthLeaderboardRow(data: row, metrics: metrics)
                }
            }
        }
    }
}

private struct PreAuthLeaderboardRowData: Identifiable {
    let id = UUID()
    let rank: String
    let avatarName: String
    let name: String
    let time: String
    let isCurrentUser: Bool
}

private struct PreAuthLeaderboardRow: View {
    let data: PreAuthLeaderboardRowData
    let metrics: PreAuthGuideMetrics

    var body: some View {
        HStack(spacing: metrics.width(10)) {
            Text(data.rank)
                .font(.montserratSemiBold(size: metrics.font(14)))
                .foregroundStyle(rowForeground)
                .frame(width: metrics.width(12), alignment: .center)

            Image(data.avatarName)
                .resizable()
                .scaledToFill()
                .frame(width: metrics.width(34), height: metrics.height(34))
                .clipShape(Circle())

            Text(data.name)
                .font(.montserratSemiBold(size: metrics.font(14)))
                .foregroundStyle(rowForeground)

            Spacer(minLength: 0)

            Text(data.time)
                .font(.montserratBold(size: metrics.font(14)))
                .foregroundStyle(rowForeground)
        }
        .padding(.horizontal, metrics.width(12))
        .frame(width: metrics.width(320), height: metrics.height(58))
        .background(
            RoundedRectangle(cornerRadius: metrics.radius(15), style: .continuous)
                .fill(data.isCurrentUser ? OnboardingValuePalette.lime.opacity(0.12) : .white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.radius(15), style: .continuous)
                        .stroke(data.isCurrentUser ? OnboardingValuePalette.lime : .white.opacity(0.12), lineWidth: 1)
                }
        )
    }

    private var rowForeground: Color {
        data.isCurrentUser ? OnboardingValuePalette.lime : .white.opacity(0.86)
    }
}

private struct PreAuthGuideMetrics {
    let size: CGSize

    private var scaleX: CGFloat { size.width / 390 }
    private var scaleY: CGFloat { size.height / 844 }
    private var typeScale: CGFloat { min(scaleX, scaleY) }

    func x(_ value: CGFloat) -> CGFloat { value * scaleX }
    func y(_ value: CGFloat) -> CGFloat { value * scaleY }
    func width(_ value: CGFloat) -> CGFloat { value * scaleX }
    func height(_ value: CGFloat) -> CGFloat { value * scaleY }
    func font(_ value: CGFloat) -> CGFloat { value * typeScale }
    func radius(_ value: CGFloat) -> CGFloat { value * typeScale }
}

private struct PreAuthGuideScreen: Identifiable {
    enum Kind {
        case landmarkCollage
        case liveTracking
        case dailyClimb
    }

    let id: String
    let kind: Kind
    let headline: String
    let subtitle: String

    static let all: [PreAuthGuideScreen] = [
        PreAuthGuideScreen(
            id: "summit_landmarks",
            kind: .landmarkCollage,
            headline: "Summit the worlds\nmost iconic landmarks",
            subtitle: "Start small and make your way up to some of the tallest points on earth."
        ),
        PreAuthGuideScreen(
            id: "real_time",
            kind: .liveTracking,
            headline: "Track your climb in\nreal-time",
            subtitle: "Connect your AirPods Pro or Max to track your climbs in realtime"
        ),
        PreAuthGuideScreen(
            id: "daily_climbs",
            kind: .dailyClimb,
            headline: "Compete live in daily\nclimbs",
            subtitle: "Join the climb of the day to complete with others for the top spot."
        )
    ]
}

#Preview {
    NavigationStack {
        PreAuthOnboardingValueCarouselScreen()
    }
}

#Preview("Guide — Summit Landmarks") {
    PreAuthGuideScreenView(
        screen: PreAuthGuideScreen.all[0],
        onBack: {},
        onContinue: {}
    )
}

#Preview("Guide — Real-Time Tracking") {
    PreAuthGuideScreenView(
        screen: PreAuthGuideScreen.all[1],
        onBack: {},
        onContinue: {}
    )
}
