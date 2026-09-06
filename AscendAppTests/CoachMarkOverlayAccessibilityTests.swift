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

        for (index, presentation) in presentations.enumerated() {
            try await verifyAccessibilityLayout(
                of: presentation,
                photographedAs: "dynamic-type-a5-\(index)"
            )
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

        try await RenderedScreen.host(root, size: Self.screenSize) { screen in
            let elements = try await settledAccessibilityElements(under: screen.window) { elements in
                elements.contains { $0.accessibilityLabel == presentation.title }
            }
            let handled = ([screen.window as NSObject] + elements).contains { element in
                element.accessibilityPerformEscape()
            }
            #expect(handled)
            #expect(probe.skipCount == 1)
        }
    }

    /// The frames prove the card and its actions stay reachable at Accessibility 5 - frames are
    /// scale-free, so nothing here needs a bitmap. The photograph, written only when
    /// `ASCEND_EVIDENCE_DIR` is set, shows the chrome around them is still readable rather than
    /// merely present.
    private func verifyAccessibilityLayout(
        of presentation: CoachMarkPresentation,
        photographedAs name: String? = nil
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

        try await RenderedScreen.host(root, size: Self.screenSize) { screen in
            let window = screen.window
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

            if let name {
                try screen.photograph(named: name)
            }
        }
    }
}

@MainActor
private final class EscapeProbe {
    var skipCount = 0
}
