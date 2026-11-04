import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// The shared kit every v3 onboarding screen builds on: the step graph, the coordinator's
/// navigation and bar origins, the answers store, the funnel contract and the route switch.
@MainActor
struct OnboardingV3KitTests {
    private func makeStore() -> PreAuthOnboardingStore {
        let suite = "onboarding-v3-kit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PreAuthOnboardingStore(userDefaults: defaults)
    }

    // MARK: - Funnel contract

    /// `orderedStepIDs` is written by hand so an index can never silently develop a gap; this holds
    /// it to the enum's members and order.
    @Test
    func theHandWrittenFunnelOrderMatchesTheStepEnum() {
        #expect(OnboardingAnalyticsContext.orderedStepIDs == OnboardingV3Step.allCases.map(\.analyticsID))
        #expect(OnboardingAnalyticsContext.currentFlowVersion == "v3")
    }

    @Test
    func theV3FunnelListsTheSeventeenStepsTheSpecNames() {
        #expect(OnboardingAnalyticsContext.orderedStepIDs == [
            "welcome", "go_harder", "get_better", "something_to_chase", "count_methods",
            "health_connect", "health_permission", "health_history", "usual_climb",
            "climber_card", "claim_city", "weekly_target", "this_month_event",
            "notification_primer", "paywall", "exit_gift", "auth"
        ])
    }

    /// The old flow still ships behind the switch, so its contexts keep their own version, order
    /// and count; switching v3 on must never relabel the funnel a v1 climber is in.
    @Test
    func theOlderFlowKeepsItsOwnVersionAndOrder() {
        let legacy = OnboardingAnalyticsContext(segmentID: "pre_auth_welcome", stepID: "welcome")
        #expect(legacy.flowVersion == "v1")
        #expect(legacy.stepCount == OnboardingAnalyticsContext.legacyOrderedStepIDs.count)
        #expect(legacy.stepIndex == 0)

        let paywall = OnboardingAnalyticsContext(segmentID: "x", stepID: "paywall")
        #expect(paywall.stepIndex == OnboardingAnalyticsContext.legacyOrderedStepIDs.count - 1)
    }

    @Test
    func aV3ContextCountsAgainstTheV3Order() {
        let coordinator = OnboardingV3Coordinator(store: makeStore(), startingAt: .healthHistory)
        let context = coordinator.analyticsContext

        #expect(context.flowVersion == "v3")
        #expect(context.stepID == "health_history")
        #expect(context.stepIndex == 7)
        #expect(context.stepCount == 17)
    }

    // MARK: - Step graph

    @Test
    func everyStepIsReachableFromTheWelcomeScreen() {
        var reached: Set<OnboardingV3Step> = [.welcome]
        var frontier: [OnboardingV3Step] = [.welcome]

        while let step = frontier.popLast() {
            let next = [step.primaryDestination].compactMap { $0 } + step.alternateExits.map(\.destination)
            for destination in next where reached.insert(destination).inserted {
                frontier.append(destination)
            }
        }

        #expect(reached == Set(OnboardingV3Step.allCases))
    }

    @Test
    func theBranchesMeetAgainAtTheClimberCard() {
        #expect(OnboardingV3Step.healthHistory.primaryDestination == .climberCard)
        #expect(OnboardingV3Step.usualClimb.primaryDestination == .climberCard)
        #expect(OnboardingV3Step.healthConnect.alternateExits.map(\.destination) == [.usualClimb])
    }

    @Test
    func thePaywallCloseOpensTheGiftAndNoThanksReturnsToThePaywall() {
        #expect(OnboardingV3Step.paywall.alternateExits.map(\.destination) == [.exitGift])
        #expect(OnboardingV3Step.exitGift.alternateExits.map(\.destination) == [.paywall])
        #expect(OnboardingV3Step.exitGift.primaryDestination == .auth)
    }

    // MARK: - Progress table

    @Test
    func theProgressTableHoldsTheDesignsValues() {
        let expected: [OnboardingV3Step: Double?] = [
            .welcome: nil, .goHarder: 38, .getBetter: 55, .somethingToChase: 67, .countMethods: 75,
            .healthConnect: 81, .healthPermission: 81, .healthHistory: 86, .usualClimb: 86,
            .climberCard: 90, .claimCity: 93, .weeklyTarget: 95, .thisMonthEvent: 97,
            .notificationPrimer: 98, .paywall: nil, .exitGift: nil, .auth: nil
        ]

        for step in OnboardingV3Step.allCases {
            #expect(OnboardingProgressTable.value(for: step) == expected[step]!, "\(step)")
        }
        #expect(OnboardingProgressTable.entryValue == 15)
    }

    // MARK: - Coordinator

    @Test
    func theFirstBarAnimatesFromFifteenAndLaterBarsFromThePreviousValue() {
        let coordinator = OnboardingV3Coordinator(store: makeStore())

        coordinator.advance()
        #expect(coordinator.step == .goHarder)
        #expect(coordinator.progressOrigin(for: .goHarder) == 15)

        coordinator.advance()
        #expect(coordinator.step == .getBetter)
        #expect(coordinator.progressOrigin(for: .getBetter) == 38)
    }

    @Test
    func goingBackAnimatesTheBarDownward() {
        let coordinator = OnboardingV3Coordinator(store: makeStore())
        coordinator.advance()
        coordinator.advance()
        coordinator.advance()
        #expect(coordinator.step == .somethingToChase)

        coordinator.back()

        #expect(coordinator.step == .getBetter)
        #expect(coordinator.progressOrigin(for: .getBetter) == 67)
        #expect((coordinator.progressOrigin(for: .getBetter) ?? 0) > (OnboardingProgressTable.value(for: .getBetter) ?? 0))
    }

    @Test
    func backRetracesTheBranchTheClimberTook() {
        let coordinator = OnboardingV3Coordinator(store: makeStore(), startingAt: .healthConnect)

        coordinator.go(to: .usualClimb)
        coordinator.advance()
        #expect(coordinator.step == .climberCard)

        coordinator.back()
        #expect(coordinator.step == .usualClimb)
        coordinator.back()
        #expect(coordinator.step == .healthConnect)
        #expect(coordinator.canGoBack == false)

        coordinator.back()
        #expect(coordinator.step == .healthConnect)
    }

    @Test
    func theWholeFlowWalksFromWelcomeToTheEnd() {
        let coordinator = OnboardingV3Coordinator(store: makeStore())
        var visited: [OnboardingV3Step] = [coordinator.step]

        while coordinator.step.primaryDestination != nil {
            coordinator.advance()
            visited.append(coordinator.step)
        }

        #expect(visited.first == .welcome)
        #expect(visited.last == .auth)
        #expect(coordinator.isFinished == false)

        coordinator.advance()
        #expect(coordinator.isFinished)
    }

    @Test
    func finishingIsPersistedAndRemembered() {
        let store = makeStore()
        let coordinator = OnboardingV3Coordinator(store: store, startingAt: .auth)

        coordinator.finish()
        let finishedAt = coordinator.answers.completedAt
        coordinator.finish()

        #expect(finishedAt != nil)
        #expect(coordinator.answers.completedAt == finishedAt)
        #expect(OnboardingV3Coordinator(store: store).isFinished)
    }

    // MARK: - Store

    @Test
    func everyAnswerRoundTripsThroughTheStore() {
        let store = makeStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let written = PreAuthOnboardingAnswers(
            usualClimbSteps: 1_800,
            usualClimbMinutes: 22,
            gender: .woman,
            birthday: PreAuthOnboardingBirthday(year: 1990, month: 4, day: 12),
            heightCm: 170,
            weightKg: 65.5,
            city: PreAuthOnboardingCity(city: "Chicago", region: "IL", countryCode: "US", countryName: "United States"),
            weeklyTargetDays: 3,
            notificationChoice: .allowed,
            foundHealthWorkoutIDs: ["a", "b"],
            welcomeGiftFirstShownAt: date,
            trialStarted: true,
            completedAt: date
        )

        store.save(written)

        #expect(store.answers() == written)
    }

    @Test
    func anEmptyOrUndecodableStoreReadsAsNothingAnswered() {
        let suite = "onboarding-v3-kit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        #expect(store.answers() == PreAuthOnboardingAnswers())

        defaults.set(Data("not json".utf8), forKey: PreAuthOnboardingStore.storageKey)
        #expect(store.answers() == PreAuthOnboardingAnswers())
        defaults.removePersistentDomain(forName: suite)
    }

    @Test
    func updateWritesThroughAndClearForgetsEverything() {
        let store = makeStore()
        let coordinator = OnboardingV3Coordinator(store: store)

        coordinator.update { $0.weeklyTargetDays = 4 }
        #expect(store.answers().weeklyTargetDays == 4)
        #expect(coordinator.answers.weeklyTargetDays == 4)

        store.clear()
        #expect(store.answers() == PreAuthOnboardingAnswers())
    }

    @Test
    func aCitySurvivesTheRoundTripThroughALocationSelection() {
        let selection = PostAuthLocationSelection(city: "Austin", region: "TX", countryCode: "US", countryName: "United States")

        #expect(PreAuthOnboardingCity(selection).selection == selection)
    }

    // MARK: - Route

    private func route(
        state: AuthenticationState,
        userId: String? = nil,
        showsV3: Bool?,
        updatePresentation: AppUpdatePresentation? = nil
    ) -> AppRootRoute {
        AppRootRouteResolver.resolve(
            updatePresentation: updatePresentation,
            authenticationState: state,
            userId: userId,
            postAuthOnboardingPhase: .complete,
            entitlementState: .inactive,
            requiredEntitlementID: "app_access",
            showsPreAuthOnboardingV3: showsV3
        )
    }

    @Test
    func signedOutWithTheSwitchOnRoutesToTheFlow() {
        #expect(route(state: .unauthenticated, showsV3: true) == .preAuthOnboarding)
    }

    @Test
    func signedOutWithTheSwitchOffKeepsTodaysLanding() {
        #expect(route(state: .unauthenticated, showsV3: false) == .signedOut)
    }

    @Test
    func theSwitchDefaultsOffSoEveryExistingCallerIsUnchanged() {
        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .unauthenticated,
            userId: nil,
            postAuthOnboardingPhase: .signedOut,
            entitlementState: .unknown,
            requiredEntitlementID: "app_access"
        )

        #expect(route == .signedOut)
    }

    @Test
    func theSwitchChangesNothingOnceTheClimberIsSigningInOrSignedIn() {
        #expect(route(state: .authenticatingWithApple, showsV3: true) == .signingIn)
        #expect(route(state: .restoringSession, showsV3: true) == .restoringSession)
        #expect(route(state: .authenticated, userId: "u1", showsV3: true) == .paywall)
    }

    /// An undecided launch never shows either flow, so a climber can never start one and be swapped
    /// into the other. Above it the lockout still wins, and a signed-in climber never sees it.
    @Test
    func anUndecidedLaunchHoldsOnlyTheSignedOutRoute() {
        #expect(route(state: .unauthenticated, showsV3: nil) == .signedOutHold)
        #expect(route(state: .restoringSession, showsV3: nil) == .restoringSession)
        #expect(route(state: .authenticated, userId: "u1", showsV3: nil) == .paywall)
        #expect(route(state: .unauthenticated, showsV3: nil, updatePresentation: .required) == .updateRequired)
    }

    @Test
    func theHoldIsAWaypointThatReportsItself() {
        #expect(AppRootRoute.signedOutHold.telemetryScreenName == .signedOutHold)
        #expect(AppLifecycleAnalyticsEvent.RootRoute(.signedOutHold) == .signedOutHold)
        #expect(AppLifecycleAnalyticsEvent.RootRoute.signedOutHold.isResolved == false)
    }

    /// The first badge on a screen pops with no delay at all, and a zero-length hold before the
    /// cubic keyframes reported a NaN scale for the whole overshoot.
    @Test(arguments: [0.0, 0.15])
    func thePopEntranceOvershootsAndSettlesAtAnyDelay(delay: Double) {
        let duration = 0.5
        let timeline = KeyframeTimeline(initialValue: OnboardingEntrance.PopFrame.start) {
            OnboardingEntrance.popKeyframes(startDelay: delay, duration: duration)
        }
        let frames = (0...200).map { timeline.value(time: (delay + duration) * Double($0) / 200) }

        #expect(frames.allSatisfy { $0.scale.isFinite && $0.opacity.isFinite })
        #expect(abs(frames[0].scale - 0.6) < 0.001)
        #expect(frames[0].opacity == 0)
        #expect(abs(timeline.value(time: delay + duration * 0.6).scale - 1.08) < 0.01)
        #expect((frames.map(\.scale).max() ?? 0) < 1.1)
        #expect(abs(frames[200].scale - 1) < 0.001)
        #expect(frames[200].opacity == 1)
    }

    @Test
    func theFlowReportsItsOwnStepsNotARouteScreen() {
        #expect(AppRootRoute.preAuthOnboarding.telemetryScreenName == nil)
        #expect(AppLifecycleAnalyticsEvent.RootRoute(.preAuthOnboarding) == .preAuthOnboarding)
        #expect(AppLifecycleAnalyticsEvent.RootRoute.preAuthOnboarding.isResolved)
    }
}
