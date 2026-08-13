import SwiftUI
import Testing
import UIKit
@testable import AscendApp

@MainActor
@Suite(.serialized, .hostsAWindow)
struct CoachMarkOverlayAccessibilityTests {
    private static let screenSize = CGSize(width: 393, height: 852)

    @Test(.bug(id: 491))
    func everyWalkthroughKeepsItsCardAndActionsReachableAtAccessibility5() async throws {
        let sharePresentations = ShareComposerCoachMark.allCases.map { mark in
            CoachMarkPresentation(
                title: mark.title,
                message: mark.message,
                stepCount: ShareComposerCoachMark.allCases.count,
                stepIndex: mark.rawValue,
                primaryActionTitle: mark == .filters ? "Got it" : "Next",
                showsSkip: true
            )
        }
        let presentations = sharePresentations + [RoutineBuilderCoachMark.timeline.presentation]

        try await withAccessibilityAutomation {
            for presentation in presentations {
                try await verifyAccessibilityLayout(of: presentation)
            }
        }
    }

    @Test(.bug(id: 491))
    func accessibilityEscapeRunsTheSameWholeWalkthroughSkipAction() async throws {
        let probe = EscapeProbe()
        let presentation = CoachMarkPresentation(
            title: "Escape test",
            message: "The modal escape action skips the walkthrough.",
            stepCount: 4,
            stepIndex: 0,
            primaryActionTitle: "Next",
            showsSkip: true
        )
        let root = CoachMarkOverlay(
            presentation: presentation,
            targetRect: CGRect(x: 24, y: 300, width: 345, height: 72),
            containerSize: Self.screenSize,
            onNext: {},
            onSkip: { probe.skipCount += 1 }
        )
        .frame(width: Self.screenSize.width, height: Self.screenSize.height)

        try await withAccessibilityAutomation {
            let controller = UIHostingController(rootView: root)
            controller.view.frame = CGRect(origin: .zero, size: Self.screenSize)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            let window = scene.map { UIWindow(windowScene: $0) }
                ?? UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
            window.frame = CGRect(origin: .zero, size: Self.screenSize)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            let elements = try await settledAccessibilityElements(under: window) { elements in
                elements.contains { $0.accessibilityLabel == presentation.title }
            }
            let handled = ([window as NSObject] + elements).contains { element in
                element.accessibilityPerformEscape()
            }
            #expect(handled)
            #expect(probe.skipCount == 1)
        }
    }

    private func verifyAccessibilityLayout(
        of presentation: CoachMarkPresentation
    ) async throws {
        let root = ZStack {
            Color.black
            CoachMarkOverlay(
                presentation: presentation,
                targetRect: CGRect(x: 24, y: 300, width: 345, height: 72),
                containerSize: Self.screenSize,
                onNext: {},
                onSkip: {}
            )
        }
        .frame(width: Self.screenSize.width, height: Self.screenSize.height)
        .environment(\.dynamicTypeSize, .accessibility5)
        .transaction { $0.disablesAnimations = true }

        let controller = UIHostingController(rootView: root)
        controller.view.frame = CGRect(origin: .zero, size: Self.screenSize)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
        window.frame = CGRect(origin: .zero, size: Self.screenSize)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        let elements: [NSObject] = try await settledAccessibilityElements(under: window) { elements in
            elements.contains { $0.accessibilityLabel == presentation.title }
                && elements.contains { $0.accessibilityLabel == "Skip" }
                && elements.contains { $0.accessibilityLabel == presentation.primaryActionTitle }
        }
        let viewport = window.convert(window.bounds, to: nil).insetBy(dx: -0.5, dy: -0.5)

        let heading = try #require(
            elements.filter { $0.accessibilityLabel == presentation.title }.first,
            "The coach-mark heading was not reachable"
        )
        #expect(viewport.contains(heading.accessibilityFrame))

        let message = try #require(
            elements.filter { $0.accessibilityLabel == presentation.message }.first,
            "The coach-mark message was not reachable"
        )
        #expect(viewport.intersects(message.accessibilityFrame))

        for label in ["Skip", presentation.primaryActionTitle] {
            let actionMatch = elements.filter { element in
                element.accessibilityLabel == label
                    && element.accessibilityTraits.contains(.button)
            }.first
            let action = try #require(
                actionMatch,
                "The \(label) action was not reachable for \(presentation.title)"
            )
            #expect(viewport.contains(action.accessibilityFrame))
            #expect(action.accessibilityFrame.width >= 44)
            #expect(action.accessibilityFrame.height >= 44)
        }
    }
}

@MainActor
private final class EscapeProbe {
    var skipCount = 0
}
