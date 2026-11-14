import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// What a climber on the welcome plan sees and can do, read off the shipping Settings screen
/// hosted in a real window: the Heads up on a Manage Subscription tap, and both buttons leaving.
@MainActor
@Suite(.hostsAWindow, .serialized)
struct CheaperPlanWarningEvidenceTests {
    private final class FixedProvider: SubscriberRateProviding {
        let snapshot: SubscriberRateSnapshot?
        init(_ snapshot: SubscriberRateSnapshot?) { self.snapshot = snapshot }
        func currentRates() async -> SubscriberRateSnapshot? { snapshot }
    }

    private static func rate(_ id: String, _ price: Decimal, _ formatted: String) -> SubscriptionRate {
        SubscriptionRate(productID: id, price: price, currencyCode: "USD", period: .year, formattedPrice: formatted)
    }

    private static func snapshot(trial: Bool) -> SubscriberRateSnapshot {
        SubscriberRateSnapshot(
            held: .subscription(
                rate: rate("ascend_yearly_welcome", 9.99, "$9.99"),
                isInFreeTrial: trial,
                willAutoRenew: true
            ),
            standardYearly: rate("ascend_yearly", 29.99, "$29.99")
        )
    }

    private func settings(
        _ snapshot: SubscriberRateSnapshot?,
        events: EventBox
    ) -> some View {
        UserDefaults.standard.set("Maya Chen", forKey: "displayName")
        let model = CheaperPlanWarningViewModel(
            provider: FixedProvider(snapshot),
            featureFlags: RemoteFeatureFlagStore(),
            track: { events.names.append($0.record.name) }
        )
        return NavigationStack {
            AccountView(cheaperPlanWarning: model)
                .environment(AuthenticationViewModel(observesFirebaseAuth: false))
        }
        .frame(width: 390, height: 1500, alignment: .top)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private final class EventBox { var names: [String] = [] }

    /// Every accessibility element in every window of the scene: a system alert is drawn in a
    /// window of its own, so the hosted screen's own tree never lists it.
    private func sceneLabels() -> [String] {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return (scene?.windows ?? []).flatMap { window in
            accessibilityElements(under: window).compactMap(\.accessibilityLabel)
                + Self.viewTexts(in: window)
        }
    }

    /// The text of every UIKit view under `view`, which is how a system alert draws its title,
    /// message and buttons.
    private static func viewTexts(in view: UIView) -> [String] {
        var texts: [String] = []
        if let label = view as? UILabel, let text = label.text { texts.append(text) }
        if let text = view.accessibilityLabel { texts.append(text) }
        for subview in view.subviews { texts += viewTexts(in: subview) }
        return texts
    }

    private static func view(labelled label: String, in view: UIView) -> UIView? {
        if view.accessibilityLabel == label || (view as? UILabel)?.text == label { return view }
        for subview in view.subviews {
            if let found = Self.view(labelled: label, in: subview) { return found }
        }
        return nil
    }

    private func waitForLabel(_ label: String, present: Bool = true) async -> Bool {
        for _ in 0..<200 {
            if sceneLabels().contains(label) == present { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Taps an alert button the way the system does: runs the handler SwiftUI gave the
    /// `UIAlertAction`. A hosted test has no touch to send, and the alert's button views are
    /// private classes that take no accessibility activation.
    private func tap(_ label: String) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        var controller: UIViewController?
        for window in scene.windows {
            var candidate = window.rootViewController
            while let current = candidate {
                if current is UIAlertController { controller = current }
                candidate = current.presentedViewController
            }
        }
        let alert = try #require(controller as? UIAlertController, "no alert is on screen")
        let action = try #require(alert.actions.first { $0.title == label }, "no \(label) action")
        let handler = try #require(action.value(forKey: "handler"), "the action has no handler")
        typealias Handler = @convention(block) (UIAlertAction) -> Void
        unsafeBitCast(handler as AnyObject, to: Handler.self)(action)
    }

    private let size = CGSize(width: 390, height: 1500)

    @Test(arguments: [false, true])
    func theHeadsUpAppearsOnTheTapWithBothButtons(inFreeTrial: Bool) async throws {
        let events = EventBox()

        try await RenderedScreen.host(
            settings(Self.snapshot(trial: inFreeTrial), events: events),
            size: size
        ) { screen in
            _ = try await screen.copy(until: { $0.contains("manage subscription") })
            // Let the read-ahead land before the tap, as it does for a climber who reads the screen.
            try await Task.sleep(for: .milliseconds(300))
            try activateAccessibilityElement(labelled: "Manage Subscription", in: screen.window)

            #expect(await waitForLabel("Keep my plan"))
            let labels = sceneLabels()
            #expect(labels.contains("Heads up"))
            #expect(labels.contains("Continue to cancel"))
            let opening = inFreeTrial ? "Your rate is $9.99 per year." : "You currently pay $9.99 per year."
            let message = try #require(labels.first { $0.contains("cheaper") })
            #expect(message == "\(opening) That's 67% cheaper than the current $29.99 per year. "
                + "If you cancel, you may not be able to get that rate again.")
            #expect(events.names == ["cheaper_plan_warning_shown"])
            try screen.photograph(named: "cheaper-plan-heads-up-\(inFreeTrial ? "trial" : "paid")")
        }
    }

    @Test
    func keepMyPlanDismissesAndNothingIsCancelled() async throws {
        let events = EventBox()

        try await RenderedScreen.host(settings(Self.snapshot(trial: false), events: events), size: size) { screen in
            _ = try await screen.copy(until: { $0.contains("manage subscription") })
            try await Task.sleep(for: .milliseconds(300))
            try activateAccessibilityElement(labelled: "Manage Subscription", in: screen.window)
            #expect(await waitForLabel("Keep my plan"))

            try tap("Keep my plan")

            #expect(await waitForLabel("Keep my plan", present: false))
            #expect(events.names == ["cheaper_plan_warning_shown", "cheaper_plan_warning_keep_tapped"])
        }
    }

    @Test
    func continueToCancelDismissesTheHeadsUpAndHandsOn() async throws {
        let events = EventBox()

        try await RenderedScreen.host(settings(Self.snapshot(trial: false), events: events), size: size) { screen in
            _ = try await screen.copy(until: { $0.contains("manage subscription") })
            try await Task.sleep(for: .milliseconds(300))
            try activateAccessibilityElement(labelled: "Manage Subscription", in: screen.window)
            #expect(await waitForLabel("Continue to cancel"))

            try tap("Continue to cancel")

            #expect(await waitForLabel("Continue to cancel", present: false))
            try await Task.sleep(for: .seconds(2))
            try screen.photograph(named: "cheaper-plan-after-continue")
            #expect(events.names == ["cheaper_plan_warning_shown", "cheaper_plan_warning_continue_tapped"])
        }
    }

    @Test
    func aClimberOnTheStandardPlanSeesNoHeadsUp() async throws {
        let events = EventBox()
        let standard = SubscriberRateSnapshot(
            held: .subscription(
                rate: Self.rate("ascend_yearly", 29.99, "$29.99"),
                isInFreeTrial: false,
                willAutoRenew: true
            ),
            standardYearly: Self.rate("ascend_yearly", 29.99, "$29.99")
        )

        try await RenderedScreen.host(settings(standard, events: events), size: size) { screen in
            _ = try await screen.copy(until: { $0.contains("manage subscription") })
            try await Task.sleep(for: .milliseconds(300))
            try activateAccessibilityElement(labelled: "Manage Subscription", in: screen.window)
            try await Task.sleep(for: .milliseconds(500))

            #expect(!sceneLabels().contains("Heads up"))
            #expect(events.names.isEmpty)
        }
    }
}
