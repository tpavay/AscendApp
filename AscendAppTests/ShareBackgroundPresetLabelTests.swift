import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The preset tile names the climb it offers, whatever its artwork is doing.
///
/// The tile draws `ClimbArtworkView` and nothing else, so for a long time the
/// only text under the button was the artwork's *placeholder* - and only the
/// `.hero` placeholder carries a name at all. A VoiceOver climber therefore
/// heard "Empire State Building" while the image was still loading and an
/// unlabelled button the moment it arrived, and the two evidence suites that
/// walk this picker passed or failed on whether the download had landed yet.
///
/// The `.card` variant is what makes this deterministic: its placeholder is a
/// bare SF Symbol, so the tile has no borrowable text in either state and needs
/// no network to prove it.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareBackgroundPresetLabelTests {
    private static let screenSize = CGSize(width: 393, height: 852)

    @Test
    func aPresetTileWithNoTextUnderItStillNamesItsClimb() async throws {
        let suiteName = "ShareBackgroundPresetLabelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ShareComposerWalkthroughStore(defaults: defaults)
        store.markSeen()

        let climb = Climb.preview
        let picker = ShareBackgroundPickerView(
            title: climb.name,
            presets: [.climbImage(climb, .card)],
            sourceOptions: .climb,
            onPick: { _ in },
            onClose: {},
            walkthrough: ShareComposerWalkthroughCoordinator(entry: .picker, store: store)
        )
        .transaction { $0.disablesAnimations = true }

        try await withAccessibilityAutomation {
            let controller = UIHostingController(rootView: picker)
            controller.overrideUserInterfaceStyle = .dark
            controller.view.frame = CGRect(origin: .zero, size: Self.screenSize)

            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            let window = scene.map { UIWindow(windowScene: $0) }
                ?? UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
            window.frame = CGRect(origin: .zero, size: Self.screenSize)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }

            _ = try await settledAccessibilityElements(under: window) { elements in
                elements.contains { $0.accessibilityLabel == "Presets" }
            }
            try activateAccessibilityElement(labelled: "Presets", in: window)

            let elements = try await settledAccessibilityElements(under: window) { elements in
                elements.contains {
                    $0.accessibilityLabel == climb.name && $0.accessibilityTraits.contains(.button)
                }
            }

            #expect(
                elements.contains {
                    $0.accessibilityLabel == climb.name && $0.accessibilityTraits.contains(.button)
                },
                """
                The preset tile published no name, so it is an unlabelled button for VoiceOver and \
                unreachable for the picker's evidence suites. Saw: \
                \(elements.map { "\(type(of: $0)): \($0.accessibilityLabel ?? "nil")" })
                """
            )
        }
    }
}
