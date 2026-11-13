import Foundation
import os.lock
import Testing
import UIKit
@testable import AscendApp

/// The fakes the app-access gate's suites share: a clock the gate sleeps on, a presenter that
/// stands in for Superwall, and an entitlement service a test can script.

/// Every wait the gate takes, held until a test fires it.
///
/// The gate tells its waits apart only by length - the opening deadline, each retry schedule - so
/// a test fires "the next 8-second wait" rather than "sleep call 3", which survives the gate
/// arming its waits in a different order.
final class GateTestClock: Sendable {
    private struct State {
        var nextID = 0
        var pending: [(id: Int, duration: Duration, continuation: CheckedContinuation<Void, any Error>)] = []
        var requested: [Duration] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var sleep: AppAccessPaywallCoordinator.Sleep {
        { [self] duration in
            let id = state.withLock { state -> Int in
                state.nextID += 1
                return state.nextID
            }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, any Error>) in
                    let isCancelled = state.withLock { state -> Bool in
                        state.requested.append(duration)
                        guard !Task.isCancelled else { return true }
                        state.pending.append((id, duration, continuation))
                        return false
                    }
                    if isCancelled {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            } onCancel: {
                let cancelled = state.withLock { state in
                    state.pending.firstIndex { $0.id == id }.map { state.pending.remove(at: $0) }
                }
                cancelled?.continuation.resume(throwing: CancellationError())
            }
        }
    }

    /// Every wait the gate has asked for, in order, fired or not.
    var requested: [Duration] {
        state.withLock { $0.requested }
    }

    /// The waits still running.
    var pending: [Duration] {
        state.withLock { $0.pending.map(\.duration) }
    }

    /// Ends the oldest running wait of that length, waiting for the gate to start it first.
    ///
    /// Bounded by a wall clock: the task that starts the wait is the gate's own, and under the
    /// full suite's load it may not have run yet.
    @discardableResult
    func fire(_ duration: Duration, timeout: Duration = .seconds(60)) async -> Bool {
        let clock = ContinuousClock()
        let giveUp = clock.now.advanced(by: timeout)
        while clock.now < giveUp {
            let fired = state.withLock { state in
                state.pending.firstIndex { $0.duration == duration }.map { state.pending.remove(at: $0) }
            }
            if let fired {
                fired.continuation.resume()
                return true
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("The gate never started a \(duration) wait. Running: \(pending)")
        return false
    }

    /// Waits until the gate is running a wait of that length, without ending it.
    @MainActor
    @discardableResult
    func waitUntilPending(_ duration: Duration, timeout: Duration = .seconds(60)) async -> Bool {
        await gateWaitUntil(timeout: timeout) { self.pending.contains(duration) }
    }
}

/// Stands in for Superwall: records what the gate asked for and lets a test answer it.
@MainActor
final class GateTestPresenter: PaywallPresenting {
    var isConfigured = true
    private(set) var cancelCount = 0
    private(set) var placements: [SuperwallPlacement] = []
    private var registeredParams: [[String: Any]?] = []
    private var handlers: [@MainActor (PaywallPresentationOutcome) -> Void] = []

    func configure(configuration: MonetizationConfiguration) {}
    func identify(userId: String) {}
    func resetIdentity() {}
    func cancelPresentation() { cancelCount += 1 }

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        placements.append(placement)
        registeredParams.append(params)
        handlers.append(onOutcome)
    }

    /// The `source` each registration carried, in order.
    var sources: [String?] {
        registeredParams.map { $0?["source"] as? String }
    }

    func params(at registration: Int) -> [String: Any]? {
        registeredParams.indices.contains(registration) ? registeredParams[registration] : nil
    }

    func send(_ outcome: PaywallPresentationOutcome, registration: Int) {
        guard handlers.indices.contains(registration) else {
            Issue.record("No registration \(registration); the gate has asked for \(placements)")
            return
        }
        handlers[registration](outcome)
    }

    /// Answers the most recent registration.
    func sendToLatest(_ outcome: PaywallPresentationOutcome) {
        send(outcome, registration: handlers.count - 1)
    }
}

@MainActor
final class GateTestEntitlementService: EntitlementServicing {
    var entitlementState: MonetizationEntitlementState = .inactive
    var hasFailedIdentityResolution = false
    var identityGeneration: MonetizationIdentityTransition?
    var isConfigured = true
    /// How many times the gate has re-read access.
    private(set) var refreshCount = 0
    /// What a refresh turns the entitlement into, by which refresh it is. Unlisted refreshes
    /// answer with whatever `entitlementState` already is.
    var stateAfterRefresh: [Int: MonetizationEntitlementState] = [:]

    init(identity: MonetizationIdentityTransition?) {
        identityGeneration = identity
    }

    func configure(configuration: MonetizationConfiguration) {}

    func refreshCustomerInfo(
        waitsForPendingIdentity: Bool
    ) async -> MonetizationEntitlementRefresh {
        refreshCount += 1
        if let state = stateAfterRefresh[refreshCount] {
            entitlementState = state
        }
        return .refreshed(entitlementState)
    }

    func prepareIdentity(
        _ customer: MonetizationCustomerIdentity
    ) -> MonetizationIdentityTransition {
        identityGeneration ?? MonetizationIdentityTransition(revision: 0, userID: customer.userID)
    }

    func identify(
        _ customer: MonetizationCustomerIdentity,
        transition: MonetizationIdentityTransition
    ) async {}

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        MonetizationIdentityTransition(revision: 0, userID: nil)
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {}
    func retryIdentityResolution() async {}

    func adoptTransactionState(
        _ state: MonetizationEntitlementState,
        for identity: MonetizationIdentityTransition
    ) -> Bool {
        guard identityGeneration == identity else { return false }
        entitlementState = state
        return true
    }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async -> MonetizationEntitlementState {
        guard identityGeneration == identity else { return .unknown }
        return entitlementState
    }

    func restorePurchases() async -> MonetizationEntitlementState {
        entitlementState
    }
}

@MainActor
final class GateTestReconciler: AppAccessReconciling {
    func reconcileAppAccess(force: Bool) async {}
}

extension AppAccessGateRetryPolicy {
    /// A schedule whose waits are all different lengths, and none of them the 8-second opening
    /// deadline, so a test can tell exactly which wait the gate is in.
    static let test = AppAccessGateRetryPolicy(
        hostedPresentationDelays: [.seconds(101), .seconds(102), .seconds(103)],
        freeWeekDelays: [.seconds(201), .seconds(202)],
        accessCheckDelays: [.seconds(301), .seconds(302)],
        routeResolutionDeadline: gateRouteDeadline
    )
}

/// The test schedule's wait for routing to leave a gate that has confirmed access.
let gateRouteDeadline: Duration = .seconds(401)

/// The gate's opening deadline, for firing it on a ``GateTestClock``.
let gateOpeningDeadline: Duration = .seconds(8)

@MainActor
func makeGateTestConfiguration() -> MonetizationConfiguration {
    MonetizationConfiguration(
        infoDictionary: [
            MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test",
            MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test",
            MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_staging_yearly",
            MonetizationConfiguration.revenueCatLifetimeProductIDInfoKey: "ascend_staging_lifetime",
            MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
        ]
    )
}

/// Waits for work the gate started on its own unstructured tasks, bounded by a wall clock rather
/// than a count of yields: under the full suite's load a fixed number of scheduler hops is not a
/// promise that another task has had its turn.
@MainActor
func gateWaitUntil(
    timeout: Duration = .seconds(60),
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}

/// Gives the gate's unstructured tasks a real chance to run, for a test that asserts something
/// did *not* happen.
@MainActor
func gateSettle() async {
    for _ in 0..<20 {
        await Task.yield()
    }
    try? await Task.sleep(for: .milliseconds(20))
}

// MARK: - Reading the spinner off a hosted screen

/// What a hosted screen shows, as far as the gate's one rule goes: a spinner, and nothing else.
struct GateSpinnerReading {
    /// Whether the system spinner is on screen and spinning.
    let showsSpinner: Bool
    /// Every accessibility label and value on screen that is not the spinner's own.
    let otherText: [String]
    /// The box around everything drawn that is not the background, in points. Nil on a flat fill.
    let inkBounds: CGRect?
    let bounds: CGRect

    /// Whether everything drawn sits in a small box at the centre of the screen: a spinner, with
    /// no line of copy and no control anywhere else.
    var isOnlyACentredSpinner: Bool {
        guard let inkBounds else { return false }
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        return inkBounds.width <= 60 && inkBounds.height <= 60
            && abs(inkBounds.midX - centre.x) <= 3
            && abs(inkBounds.midY - centre.y) <= 3
    }
}

extension HostedScreen {
    /// Reads the screen against the gate's rule. The ink is read off a 1x capture, so a caption,
    /// a button or a headline anywhere on the screen widens the box and fails the reading.
    func gateSpinnerReading() async throws -> GateSpinnerReading {
        _ = await gateWaitUntil(timeout: .seconds(10)) { self.isGateSpinnerMounted }
        try await settle(.turns(2, interval: .milliseconds(20)))

        let spinner = Self.gateSpinner(under: window)
        // The system spinner speaks for itself - "In progress" - and that is not copy Ascend drew.
        let spinnerFrame = spinner?.accessibilityFrame.insetBy(dx: -2, dy: -2)
        let otherText = accessibilityElements(under: window)
            .filter { element in
                guard !element.accessibilityElementsHidden else { return false }
                guard let spinnerFrame, !element.accessibilityFrame.isEmpty else { return true }
                return !spinnerFrame.contains(element.accessibilityFrame)
            }
            .flatMap { [$0.accessibilityLabel, $0.accessibilityValue] }
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let inkBounds = try withPixels { $0.bounds { $0.luminance > 24 } }
        return GateSpinnerReading(
            showsSpinner: spinner != nil,
            otherText: otherText,
            inkBounds: inkBounds,
            bounds: bounds
        )
    }

    /// Whether the spinner is mounted right now, without waiting for it. For a test that expects
    /// it gone, or that only needs to know the gate is still behind something presented over it.
    var isGateSpinnerMounted: Bool {
        Self.gateSpinner(under: window) != nil
    }

    /// `ProgressView()` is the system activity indicator, so that is what the gate is found by:
    /// a custom drawing standing in for it would not be the normal spinner.
    private static func gateSpinner(under view: UIView) -> UIActivityIndicatorView? {
        if let indicator = view as? UIActivityIndicatorView,
           indicator.isAnimating, !indicator.isHidden, indicator.window != nil {
            return indicator
        }
        for subview in view.subviews {
            if let found = gateSpinner(under: subview) { return found }
        }
        return nil
    }
}

/// Asserts the hosted screen is the gate's spinner and nothing else.
@MainActor
func expectOnlyTheGateSpinner(
    on screen: HostedScreen,
    _ state: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let reading = try await screen.gateSpinnerReading()
    #expect(
        reading.showsSpinner,
        "\(state): the system spinner is not on screen",
        sourceLocation: sourceLocation
    )
    #expect(
        reading.otherText.isEmpty,
        "\(state): the gate published copy of its own: \(reading.otherText)",
        sourceLocation: sourceLocation
    )
    #expect(
        reading.isOnlyACentredSpinner,
        "\(state): something other than a centred spinner is drawn. Ink: \(String(describing: reading.inkBounds)) in \(reading.bounds)",
        sourceLocation: sourceLocation
    )
}
