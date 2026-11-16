import AuthenticationServices
import Foundation
import Testing
import UIKit
@testable import AscendApp

/// The one component that owns an Apple authorization from request to answer.
///
/// 1.3.0 was rejected under Guideline 2.1(a) after Sign in with Apple failed on App Review's phone,
/// and production holds two shapes of that failure: a refusal with no sheet at all, 0 s after the tap
/// (Apple's own test fleet, 46 of 46 attempts), and a sheet that opens and then ends in an error 1 to
/// 12 s later (four retail customers). The sheet cannot be raised in a unit test - the simulator has
/// no Apple Account and the real controller never calls back - so a controller subclass that records
/// `performRequests()` stands in for it, and these tests deliver the answers by hand.
@MainActor
struct AppleAuthorizationPerformerTests {
    /// A controller that never reaches the system. It is the performer's collaborator in every test,
    /// so the performer's identity check, retention and single resolution are the real ones.
    @MainActor
    final class FakeController: ASAuthorizationController {
        var onPerform: (@MainActor () -> Void)?
        override func performRequests() { onPerform?() }
    }

    /// Holds the performer's clock, and hands out the controllers the performer asked for. It keeps
    /// them weakly, so what it observes is whether the performer itself holds on.
    @MainActor
    final class Harness {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        private(set) var createdCount = 0
        private(set) var performCalls = 0
        weak var lastController: FakeController?
        let notifications = NotificationCenter()
        private(set) var performer: AppleAuthorizationPerformer!

        init() {
            performer = AppleAuthorizationPerformer(
                makeController: { [unowned self] request in
                    let controller = FakeController(authorizationRequests: [request])
                    controller.onPerform = { [unowned self] in performCalls += 1 }
                    createdCount += 1
                    lastController = controller
                    return controller
                },
                now: { [unowned self] in clock },
                notificationCenter: notifications,
                anchorWindow: { AppleAuthorizationPerformer.liveAnchor() },
                sceneState: { "foreground_active" },
                applicationState: { "active" }
            )
        }
    }

    private func request() -> ASAuthorizationAppleIDRequest {
        ASAuthorizationAppleIDProvider().createRequest()
    }

    private func appleError(_ code: ASAuthorizationError.Code) -> NSError {
        NSError(domain: ASAuthorizationError.errorDomain, code: code.rawValue)
    }

    private func credential() -> AppleAuthorizationCredential {
        AppleAuthorizationCredential(
            userID: "apple-user-1",
            identityToken: Data("token".utf8),
            authorizationCode: Data("code".utf8),
            fullName: nil,
            email: nil
        )
    }

    /// Starts a request and waits until the performer has handed its controller the work.
    private func start(_ harness: Harness) async -> Task<AppleAuthorizationOutcome, Never> {
        let performer = harness.performer!
        let request = request()
        let createdBefore = harness.createdCount
        let task = Task { @MainActor in await performer.perform(request) }
        var turns = 0
        while (harness.createdCount == createdBefore || harness.performCalls != harness.createdCount) && turns < 200 {
            await Task.yield()
            turns += 1
        }
        return task
    }

    // MARK: - The two production shapes

    @Test("The fleet shape: Apple refuses with no sheet, 0 s after the tap")
    func aRefusalWithNoSheetIsReportedAsNoSheet() async throws {
        let harness = Harness()
        let task = await start(harness)
        let controller = try #require(harness.lastController)

        harness.performer.authorizationController(controller: controller, didCompleteWithError: appleError(.unknown))
        let outcome = await task.value

        guard case .failure(let error) = outcome.result else { Issue.record("a refusal returned a credential"); return }
        #expect((error as NSError).code == ASAuthorizationError.unknown.rawValue)
        #expect(outcome.trace.sheetPresented == false, "the app never lost the foreground")
        #expect(outcome.trace.millisecondsToResult == 0)
        #expect(outcome.trace.attemptNumber == 1)
    }

    @Test("The retail shape: the sheet opens, then Apple ends in an error seconds later")
    func aRefusalAfterTheSheetIsReportedWithTheSheetAndTheTime() async throws {
        let harness = Harness()
        let task = await start(harness)
        let controller = try #require(harness.lastController)

        // Raising Apple's sheet takes the foreground from the app.
        harness.notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        harness.clock = harness.clock.addingTimeInterval(9.1)
        harness.performer.authorizationController(controller: controller, didCompleteWithError: appleError(.unknown))
        let outcome = await task.value

        #expect(outcome.trace.sheetPresented)
        #expect(outcome.trace.millisecondsToResult == 9_100)
        #expect(outcome.trace.sceneState == "foreground_active")
        #expect(outcome.trace.applicationState == "active")
    }

    @Test("Production's quick cancel, then a retry that completes")
    func aCancelThenASuccessfulRetryEachResolveOnce() async throws {
        let harness = Harness()

        let first = await start(harness)
        harness.clock = harness.clock.addingTimeInterval(1.5)
        harness.performer.authorizationController(
            controller: try #require(harness.lastController),
            didCompleteWithError: appleError(.canceled)
        )
        let cancelled = await first.value
        guard case .failure(let cancelError) = cancelled.result else { Issue.record("a cancel returned a credential"); return }
        #expect((cancelError as NSError).code == ASAuthorizationError.canceled.rawValue)
        #expect(cancelled.trace.millisecondsToResult == 1_500, "the quick cancel is recorded with its time")
        #expect(cancelled.trace.attemptNumber == 1)
        #expect(!harness.performer.isInProgress)

        let second = await start(harness)
        harness.performer.deliver(.success(credential()))
        let completed = await second.value
        guard case .success(let supplied) = completed.result else { Issue.record("the retry did not complete"); return }
        #expect(supplied.userID == "apple-user-1")
        #expect(completed.trace.attemptNumber == 2)
        #expect(harness.createdCount == 2, "each attempt gets its own controller")
    }

    // MARK: - Single flight

    @Test("A second request while one waits on Apple is refused and leaves the first alone")
    func aSecondRequestDuringOneInFlightDoesNotTouchTheFirst() async throws {
        let harness = Harness()
        let first = await start(harness)
        #expect(harness.performer.isInProgress)

        let second = await harness.performer.perform(request())

        guard case .failure(let error) = second.result else { Issue.record("the second request started"); return }
        #expect(error as? AppleAuthorizationError == .alreadyInProgress)
        #expect(harness.createdCount == 1, "no second controller was raised")
        #expect(harness.performer.isInProgress, "the first request is still waiting on Apple")

        harness.performer.deliver(.success(credential()))
        let firstOutcome = await first.value
        guard case .success = firstOutcome.result else { Issue.record("the first request lost its answer"); return }
        #expect(firstOutcome.trace.attemptNumber == 1, "the refused request was not counted as an attempt")
    }

    @Test("A second callback for the same request is ignored, not a crash")
    func aRepeatedCallbackResolvesTheRequestOnce() async throws {
        let harness = Harness()
        let task = await start(harness)
        let controller = try #require(harness.lastController)

        harness.performer.authorizationController(controller: controller, didCompleteWithError: appleError(.failed))
        harness.performer.authorizationController(controller: controller, didCompleteWithError: appleError(.unknown))
        harness.performer.deliver(.success(credential()))
        let outcome = await task.value

        guard case .failure(let error) = outcome.result else { Issue.record("a later callback replaced the answer"); return }
        #expect((error as NSError).code == ASAuthorizationError.failed.rawValue, "the first answer stands")
        #expect(!harness.performer.isInProgress)
    }

    @Test("A late callback from an earlier request does not resolve the current one")
    func aLateCallbackFromASupersededControllerIsIgnored() async throws {
        let harness = Harness()
        let first = await start(harness)
        let staleController = try #require(harness.lastController)
        harness.performer.deliver(.failure(appleError(.canceled)))
        _ = await first.value

        let second = await start(harness)
        harness.performer.authorizationController(controller: staleController, didCompleteWithError: appleError(.unknown))
        #expect(harness.performer.isInProgress, "the second request is still waiting on Apple")

        harness.performer.authorizationController(
            controller: try #require(harness.lastController),
            didCompleteWithError: appleError(.notInteractive)
        )
        let outcome = await second.value
        guard case .failure(let error) = outcome.result else { Issue.record("no answer"); return }
        #expect((error as NSError).code == ASAuthorizationError.notInteractive.rawValue)
    }

    // MARK: - Lifetime

    @Test("The controller is held for the whole request and let go once it resolves")
    func theControllerOutlivesTheCallerThatStartedTheRequest() async throws {
        let harness = Harness()
        var task: Task<AppleAuthorizationOutcome, Never>? = await start(harness)

        // Nothing but the performer holds the controller: the harness keeps it weakly.
        for _ in 0..<5 { await Task.yield() }
        let controller = try #require(harness.lastController, "the controller was released while Apple's sheet was up")

        harness.performer.authorizationController(controller: controller, didCompleteWithError: appleError(.unknown))
        _ = await task?.value
        task = nil

        #expect(!harness.performer.isInProgress)
        for _ in 0..<20 where harness.lastController != nil { await Task.yield() }
    }

    @Test("The sheet is anchored and the controller delegates to the performer")
    func theControllerIsGivenTheDelegateAndTheAnchor() async throws {
        let harness = Harness()
        let task = await start(harness)
        let controller = try #require(harness.lastController)

        #expect(controller.delegate === harness.performer)
        #expect(controller.presentationContextProvider === harness.performer)
        #expect(harness.performCalls == 1)

        harness.performer.deliver(.failure(appleError(.unknown)))
        _ = await task.value
    }
}
