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
    func theV3FunnelListsTheFifteenStepsAndEndsAtSignIn() {
        #expect(OnboardingAnalyticsContext.orderedStepIDs == [
            "welcome", "go_harder", "get_better", "something_to_chase", "count_methods",
            "health_connect", "health_permission", "health_history", "usual_climb",
            "climber_card", "claim_city", "weekly_target", "this_month_event",
            "notification_primer", "auth"
        ])
        #expect(!OnboardingAnalyticsContext.orderedStepIDs.contains("paywall"))
        #expect(!OnboardingAnalyticsContext.orderedStepIDs.contains("exit_gift"))
    }

    /// The paywall is not a v3 step, but it still reports under the v3 pass that led to it, one
    /// position past the last step, so a funnel on `flow_version=v3` reads it as the hand-off.
    @Test
    func theV3PaywallReportsAsTheHandOffPastTheLastStep() {
        let v3 = OnboardingAnalyticsContext.paywallHandOff(flowVersion: "v3")

        #expect(v3.flowVersion == "v3")
        #expect(v3.stepID == "paywall")
        #expect(v3.stepCount == 15)
        #expect(v3.stepIndex == 15)

        let v1 = OnboardingAnalyticsContext.paywallHandOff(flowVersion: "v1")
        #expect(v1 == OnboardingAnalyticsEvent.paywallContext)
        #expect(v1.stepIndex == OnboardingAnalyticsContext.legacyOrderedStepIDs.count - 1)
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
        #expect(context.stepCount == 15)
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
        #expect(OnboardingV3Step.healthHistory.primaryDestination == .profileSetup)
        #expect(OnboardingV3Step.usualClimb.primaryDestination == .profileSetup)
        #expect(OnboardingV3Step.healthConnect.alternateExits.map(\.destination) == [.usualClimb])
    }

    @Test
    func signInIsTheLastStepAndNoTapOnItsScreenLeavesIt() {
        #expect(OnboardingV3Step.notificationPrimer.primaryDestination == .auth)
        #expect(OnboardingV3Step.auth.primaryDestination == nil)
        #expect(OnboardingV3Step.welcome.alternateExits.map(\.destination) == [.auth])
        #expect(OnboardingV3Step.allCases.last == .auth)
    }

    // MARK: - Progress table

    @Test
    func theProgressTableHoldsTheDesignsValues() {
        let expected: [OnboardingV3Step: Double?] = [
            .welcome: nil, .goHarder: 38, .getBetter: 55, .somethingToChase: 67, .countMethods: 75,
            .healthConnect: 81, .healthPermission: 81, .healthHistory: 86, .usualClimb: 86,
            .profileSetup: 90, .claimCity: 93, .weeklyTarget: 95, .thisMonthEvent: 97,
            .notificationPrimer: 98, .auth: nil
        ]

        for step in OnboardingV3Step.allCases {
            #expect(OnboardingProgressTable.value(for: step) == expected[step]!, "\(step)")
        }
        #expect(OnboardingProgressTable.entryValue == 15)
    }

    // MARK: - Coordinator

    @Test
    func theFirstBarAnimatesFromFifteenAndLaterBarsFromThePreviousValue() {
        let coordinator = OnboardingV3Coordinator(store: makeStore(), now: everyTapAfterTheTransition())

        coordinator.advance()
        #expect(coordinator.step == .goHarder)
        #expect(coordinator.progressOrigin(for: .goHarder) == 15)

        coordinator.advance()
        #expect(coordinator.step == .getBetter)
        #expect(coordinator.progressOrigin(for: .getBetter) == 38)
    }

    @Test
    func twoQuickTapsAdvanceExactlyOneScreen() {
        var clock = ContinuousClock.now
        let coordinator = OnboardingV3Coordinator(store: makeStore(), now: { clock })

        coordinator.advance()
        coordinator.advance()
        #expect(coordinator.step == .goHarder)

        clock += .milliseconds(249)
        coordinator.advance()
        #expect(coordinator.step == .goHarder)

        clock += .milliseconds(1)
        coordinator.advance()
        #expect(coordinator.step == .getBetter)
    }

    @Test
    func goingBackAnimatesTheBarDownward() {
        let coordinator = OnboardingV3Coordinator(store: makeStore(), now: everyTapAfterTheTransition())
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
        let coordinator = OnboardingV3Coordinator(store: makeStore(), startingAt: .healthConnect, now: everyTapAfterTheTransition())

        coordinator.go(to: .usualClimb)
        coordinator.advance()
        #expect(coordinator.step == .profileSetup)

        coordinator.back()
        #expect(coordinator.step == .usualClimb)
        coordinator.back()
        #expect(coordinator.step == .healthConnect)
        #expect(coordinator.canGoBack == false)

        coordinator.back()
        #expect(coordinator.step == .healthConnect)
    }

    @Test
    func theSignedOutFlowWalksFromWelcomeToSignInAndStopsThere() {
        let coordinator = OnboardingV3Coordinator(store: makeStore(), now: everyTapAfterTheTransition())
        var visited: [OnboardingV3Step] = [coordinator.step]

        while coordinator.step.primaryDestination != nil {
            coordinator.advance()
            visited.append(coordinator.step)
        }

        #expect(visited.first == .welcome)
        #expect(visited.last == .auth)
        #expect(coordinator.isFinished == false)

        coordinator.advance()
        #expect(coordinator.step == .auth, "a tap cannot move past sign-in")
        #expect(coordinator.isFinished == false)
    }

    @Test
    func signingInEndsTheSignedOutFlowForGood() {
        let coordinator = OnboardingV3Coordinator(store: makeStore(), startingAt: .auth)

        coordinator.finish()
        let finishedAt = coordinator.answers.completedAt
        coordinator.finish()

        #expect(finishedAt != nil)
        #expect(coordinator.answers.completedAt == finishedAt, "a second finish keeps the first time")
        #expect(coordinator.isFinished)
        #expect(coordinator.step == .auth)
    }

    @Test
    func signingOutDoesNotRestartTheFlow() {
        let coordinator = OnboardingV3Coordinator(store: makeStore(), startingAt: .auth)
        coordinator.finish()

        coordinator.sessionEnded()

        #expect(coordinator.isFinished, "signing out does not restart the flow")
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
        updatePresentation: AppUpdatePresentation? = nil,
        entitlementState: MonetizationEntitlementState = .inactive
    ) -> AppRootRoute {
        AppRootRouteResolver.resolve(
            updatePresentation: updatePresentation,
            authenticationState: state,
            userId: userId,
            postAuthOnboardingPhase: .complete,
            entitlementState: entitlementState,
            requiredEntitlementID: "app_access",
            showsPreAuthOnboardingV3: showsV3
        )
    }

    /// The flow ends at sign-in, and what a climber without access meets next is the app-access
    /// gate: the Superwall paywall (placement `app_access_gate`), with the native plan list as its
    /// fallback. There is no second route for the new onboarding.
    @Test
    func aSignedInClimberWithoutAccessGoesToTheAppAccessGate() {
        #expect(route(state: .authenticated, userId: "u1", showsV3: false) == .paywall)
    }

    @Test
    func aSignedInClimberWhoAlreadyPaysGoesStraightToTheApp() {
        let paying = route(
            state: .authenticated, userId: "u1", showsV3: false,
            entitlementState: .active(["app_access"])
        )

        #expect(paying == .mainApp)
    }

    @Test
    func theGateWaitsForTheEntitlementInsteadOfGuessing() {
        let unknown = route(
            state: .authenticated, userId: "u1", showsV3: false,
            entitlementState: .unknown
        )

        #expect(unknown == .resolving)
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

/// A clock for a test that walks the flow one tap at a time: each reading is a second after the
/// last, so no tap lands inside the transition the one before it started.
func everyTapAfterTheTransition() -> () -> ContinuousClock.Instant {
    var instant = ContinuousClock.now
    return {
        instant += .seconds(1)
        return instant
    }
}
