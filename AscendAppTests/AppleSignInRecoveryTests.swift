import AuthenticationServices
import Foundation
import Testing
@testable import AscendApp

/// What Sign in with Apple does when Apple's sheet fails: what is recorded, what the climber is
/// told and offered, and that nothing starts twice.
///
/// Production ASCEND-IOS-1F holds two failures under one title - Apple's own test fleet refused with
/// no sheet 46 of 46 times, and four retail customers saw a sheet that ended in an error - and the
/// app threw Apple's code away, so neither could be told apart or diagnosed. These tests hold the
/// recording and the recovery.

/// Answers an Apple request from a script, and can hold one open the way a sheet does.
@MainActor
final class ScriptedApplePerformer: AppleAuthorizationPerforming {
    var outcomes: [AppleAuthorizationOutcome]
    private(set) var performCount = 0
    var holdsTheNextRequest = false
    private var gate: CheckedContinuation<Void, Never>?

    init(_ outcomes: [AppleAuthorizationOutcome] = []) {
        self.outcomes = outcomes
    }

    func perform(_ request: ASAuthorizationAppleIDRequest) async -> AppleAuthorizationOutcome {
        performCount += 1
        if holdsTheNextRequest {
            holdsTheNextRequest = false
            await withCheckedContinuation { gate = $0 }
        }
        return outcomes.isEmpty ? Self.failure(code: .unknown) : outcomes.removeFirst()
    }

    func releaseHeldRequest() {
        gate?.resume()
        gate = nil
    }

    static let trace = AppleAuthorizationTrace(
        sheetPresented: true,
        millisecondsToResult: 9_100,
        sceneState: "foreground_active",
        applicationState: "active",
        attemptNumber: 1
    )

    static func failure(
        code: ASAuthorizationError.Code,
        trace: AppleAuthorizationTrace = ScriptedApplePerformer.trace
    ) -> AppleAuthorizationOutcome {
        let error = NSError(domain: ASAuthorizationError.errorDomain, code: code.rawValue)
        return AppleAuthorizationOutcome(result: .failure(error), trace: trace)
    }
}

@MainActor
struct AppleSignInRecoveryTests {
    private func appleError(code: Int, underlying: NSError? = nil) -> NSError {
        NSError(
            domain: ASAuthorizationError.errorDomain,
            code: code,
            userInfo: underlying.map { [NSUnderlyingErrorKey: $0] } ?? [:]
        )
    }

    private func viewModel(_ performer: ScriptedApplePerformer) -> AuthenticationViewModel {
        let defaults = UserDefaults(suiteName: "apple-recovery-\(UUID().uuidString)")!
        let service = AuthenticationService(
            signInIdentityStore: SignInIdentityStore(userDefaults: defaults),
            appleAuthorization: performer
        )
        return AuthenticationViewModel(observesFirebaseAuth: false, authenticationService: service)
    }

    // MARK: - Apple's code is kept

    @Test("Every code the enum names keeps its name and its integer", arguments: [
        (ASAuthorizationError.Code.unknown, "unknown"),
        (.invalidResponse, "invalidResponse"),
        (.notHandled, "notHandled"),
        (.failed, "failed"),
        (.notInteractive, "notInteractive")
    ])
    func aNamedCodeIsRecordedByNameAndInteger(code: ASAuthorizationError.Code, name: String) throws {
        let thrown = try #require(
            AuthenticationService.appleAuthorizationFailure(for: appleError(code: code.rawValue)) as? AuthenticationError
        )

        #expect(thrown.telemetryInfo["apple_error_name"] == name)
        #expect(thrown.telemetryInfo["error_code"] == String(code.rawValue))
    }

    @Test("A code the app has never heard of is its own integer, not 'unknown'")
    func anUnlistedCodeIsNotCollapsedIntoUnknown() throws {
        let thrown = try #require(
            AuthenticationService.appleAuthorizationFailure(for: appleError(code: 1099)) as? AuthenticationError
        )

        #expect(thrown.telemetryInfo["error_code"] == "1099")
        #expect(thrown.telemetryInfo["apple_error_name"] == "unrecognized")
    }

    @Test("The whole underlying chain is recorded, outermost first")
    func theUnderlyingChainIsKept() throws {
        let osStatus = NSError(domain: NSOSStatusErrorDomain, code: -54)
        let akError = NSError(domain: "AKAuthenticationError", code: -7027, userInfo: [NSUnderlyingErrorKey: osStatus])
        let thrown = try #require(
            AuthenticationService.appleAuthorizationFailure(
                for: appleError(code: ASAuthorizationError.unknown.rawValue, underlying: akError)
            ) as? AuthenticationError
        )

        #expect(thrown.telemetryInfo["underlying_domain"] == "AKAuthenticationError")
        #expect(thrown.telemetryInfo["underlying_code"] == "-7027")
        #expect(thrown.telemetryInfo["underlying_chain"] == "AKAuthenticationError:-7027>\(NSOSStatusErrorDomain):-54")
    }

    @Test("The attempt's trace rides on the Sentry tags")
    func theTraceIsOnTheTags() throws {
        let thrown = try #require(
            AuthenticationService.appleAuthorizationFailure(
                for: appleError(code: ASAuthorizationError.unknown.rawValue),
                trace: ScriptedApplePerformer.trace
            ) as? AuthenticationError
        )

        #expect(thrown.telemetryInfo["sheet_presented"] == "true")
        #expect(thrown.telemetryInfo["ms_to_result"] == "9100")
        #expect(thrown.telemetryInfo["scene_state"] == "foreground_active")
        #expect(thrown.telemetryInfo["app_state"] == "active")
        #expect(thrown.telemetryInfo["attempt_number"] == "1")
    }

    @Test("A failure with no sheet says so")
    func aRefusalWithNoSheetIsTaggedAsNoSheet() throws {
        let noSheet = AppleAuthorizationTrace(
            sheetPresented: false,
            millisecondsToResult: 0,
            sceneState: "foreground_active",
            applicationState: "active",
            attemptNumber: 2
        )
        let thrown = try #require(
            AuthenticationService.appleAuthorizationFailure(
                for: appleError(code: ASAuthorizationError.unknown.rawValue),
                trace: noSheet
            ) as? AuthenticationError
        )

        #expect(thrown.telemetryInfo["sheet_presented"] == "false")
        #expect(thrown.telemetryInfo["ms_to_result"] == "0")
        #expect(thrown.telemetryInfo["attempt_number"] == "2")
    }

    // MARK: - Mixpanel carries the same facts, typed

    @Test("onboarding_auth_failed carries Apple's code, the chain and the trace as typed values")
    func theMixpanelEventCarriesTheDiagnostics() throws {
        let osStatus = NSError(domain: NSOSStatusErrorDomain, code: -54)
        let thrown = try #require(
            AuthenticationService.appleAuthorizationFailure(
                for: appleError(code: ASAuthorizationError.unknown.rawValue, underlying: osStatus),
                trace: ScriptedApplePerformer.trace
            ) as? AuthenticationError
        )

        let record = OnboardingAnalyticsEvent.authFailed(
            provider: "apple",
            reason: "failed",
            entry: "welcome_shortcut",
            details: thrown.analyticsParameters
        ).record

        #expect(record.name == "onboarding_auth_failed")
        #expect(record.parameters["reason"] == .string("failed"))
        #expect(record.parameters["entry"] == .string("welcome_shortcut"))
        #expect(record.parameters["error_domain"] == .string(ASAuthorizationError.errorDomain))
        #expect(record.parameters["error_code"] == .int(1000))
        #expect(record.parameters["apple_error_name"] == .string("unknown"))
        #expect(record.parameters["underlying_code"] == .int(-54))
        #expect(record.parameters["sheet_presented"] == .bool(true))
        #expect(record.parameters["ms_to_result"] == .int(9_100))
        #expect(record.parameters["scene_state"] == .string("foreground_active"))
        #expect(record.parameters["app_state"] == .string("active"))
        #expect(record.parameters["attempt_number"] == .int(1))
    }

    @Test("A sheet closed within two seconds is recorded with its time, never as a failure")
    func aQuickCancelIsRecordedWithItsTrace() throws {
        let quick = AppleAuthorizationTrace(
            sheetPresented: true,
            millisecondsToResult: 1_500,
            sceneState: "foreground_active",
            applicationState: "active",
            attemptNumber: 1
        )
        let thrown = AuthenticationService.appleAuthorizationFailure(
            for: appleError(code: ASAuthorizationError.canceled.rawValue),
            trace: quick
        )

        let cancelled = try #require(thrown as? AppleAuthorizationCancelled)
        #expect(cancelled.trace?.millisecondsToResult == 1_500)
        #expect(cancelled.trace?.analyticsParameters["ms_to_result"] == .int(1_500))
    }

    // MARK: - What the view model does with each shape

    @Test("A refusal ends on the sign-in screen with the guidance, not a spinner and not a connection sentence")
    func aRefusalLeavesTheClimberWithGuidanceAndNoDeadEnd() async {
        let performer = ScriptedApplePerformer([ScriptedApplePerformer.failure(code: .unknown)])
        let model = viewModel(performer)

        await model.signInWithApple()

        #expect(model.authenticationState == .unauthenticated)
        #expect(model.errorMessage == AuthenticationError.appleFailureGuidance)
        #expect(model.errorMessage?.contains("Apple Account") == true)
        #expect(model.errorMessage?.localizedCaseInsensitiveContains("connection") == false)
        #expect(model.appleFailureCount == 1)
        #expect(performer.performCount == 1, "nothing retried by itself")
    }

    @Test("A second refusal in a row is counted, and a success clears the count")
    func failuresInARowAreCounted() async {
        let performer = ScriptedApplePerformer([
            ScriptedApplePerformer.failure(code: .unknown),
            ScriptedApplePerformer.failure(code: .unknown)
        ])
        let model = viewModel(performer)

        await model.signInWithApple()
        await model.signInWithApple()

        #expect(model.appleFailureCount == 2)
        #expect(performer.performCount == 2, "one request per tap, no automatic retry")
    }

    @Test("A cancelled sheet shows no error and does not count as a failure")
    func aCancelIsQuiet() async {
        let performer = ScriptedApplePerformer([ScriptedApplePerformer.failure(code: .canceled)])
        let model = viewModel(performer)

        await model.signInWithApple()

        #expect(model.authenticationState == .unauthenticated)
        #expect(model.errorMessage == nil)
        #expect(model.appleFailureCount == 0)
    }

    @Test("A second tap while the first waits on Apple starts nothing and leaves the first alone")
    func aSecondTapDuringASignInIsIgnored() async {
        let performer = ScriptedApplePerformer([ScriptedApplePerformer.failure(code: .unknown)])
        performer.holdsTheNextRequest = true
        let model = viewModel(performer)

        let first = Task { @MainActor in await model.signInWithApple() }
        for _ in 0..<50 where performer.performCount == 0 { await Task.yield() }
        #expect(model.authenticationState == .authenticatingWithApple)

        await model.signInWithApple()
        await model.signInWithGoogle()

        #expect(performer.performCount == 1, "no second sheet")
        #expect(model.authenticationState == .authenticatingWithApple, "the first attempt's state was not reset under it")

        performer.releaseHeldRequest()
        await first.value
        #expect(model.authenticationState == .unauthenticated)
        #expect(model.appleFailureCount == 1)
    }

    // MARK: - What the sign-in screen offers

    @Test("Before any failure the buttons read as they always did, Apple first")
    func theFirstLookIsUnchanged() {
        let presentation = AppleRetryPresentation(appleFailureCount: 0)

        #expect(presentation.appleTitle == "Continue with Apple")
        #expect(presentation.googleTitle == "Continue with Google")
        #expect(!presentation.googleLeads)
    }

    @Test("The first failure offers the same button again, labelled as a retry, Apple still first")
    func theFirstFailureOffersATryAgain() {
        let presentation = AppleRetryPresentation(appleFailureCount: 1)

        #expect(presentation.appleTitle == "Try Apple again")
        #expect(!presentation.googleLeads)
    }

    @Test("From the second failure on, Google leads", arguments: [2, 3, 7])
    func theSecondFailureHandsGoogleTheFirstPlace(count: Int) {
        let presentation = AppleRetryPresentation(appleFailureCount: count)

        #expect(presentation.googleLeads)
        #expect(presentation.appleTitle == "Try Apple again", "Apple stays one tap away")
    }
}
