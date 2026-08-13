import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The clusters photographed on the surface a climber taps them from.
///
/// `ShareStatClusterPresetEvidenceTests` exports what the shared image looks
/// like; nothing there shows the picker itself. This hosts the shipping
/// `ShareComposerView` in a phone-sized window, walks it the way a climber does
/// - pick a background, the add sheet opens on its own - and photographs the
/// GROUPS grid, then taps a group and photographs the canvas it lands on.
///
/// The screens are the real ones: no stand-in sheet, no re-implemented tile.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareStatClusterPickerEvidenceTests {
    private static let screenSize = CGSize(width: 393, height: 852)

    @Test
    func theGroupsPickerAndAPlacedClusterArePhotographed() async throws {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Live Climb",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true
        )
        context.insert(workout)
        try context.save()

        let composer = ShareComposerView(
            workout: workout,
            climb: .preview,
            liveClimbRank: 4,
            liveClimbRankTotal: 1_284
        )
        .modelContainer(container)

        try await withAccessibilityAutomation {
            let controller = UIHostingController(rootView: composer)
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

            _ = try await settledAccessibilityElements(under: controller.view)

            // The climber picks the climb's own artwork as a background; the add
            // sheet then opens by itself, which is where the groups live.
            try activateAccessibilityElement(labelled: "Presets", in: controller.view)
            try await settle(window)
            try activateAccessibilityElement(in: controller.view) {
                $0.accessibilityLabel == Climb.preview.name && $0.accessibilityTraits.contains(.button)
            }
            try await settle(window, seconds: 1.2)

            // A tile reads out everything it draws and ends on its own name, so
            // the labels below are also what a VoiceOver climber hears.
            let sheetLabels = try await settledAccessibilityElements(under: window) {
                $0.contains { $0.accessibilityLabel?.hasSuffix("HERO") == true }
            }.compactMap(\.accessibilityLabel)
            #expect(
                ["HERO", "RANK", "ROW", "SPLITS", "RECEIPT", "MINIMAL",
                 "HR HERO", "HR ROW", "FULL GRID", "HR MINIMAL"].allSatisfy { title in
                    sheetLabels.contains { $0.hasSuffix(title) }
                },
                "the add sheet did not show every group. Saw: \(sheetLabels)"
            )
            try Self.photograph(window, named: "share-cluster-picker-1-groups-grid")

            // Tapping a group drops it on the canvas as one sticker.
            try activateAccessibilityElement(in: window) {
                $0.accessibilityLabel?.hasSuffix(", SPLITS") == true
            }
            try await settle(window, seconds: 1.0)
            try Self.photograph(window, named: "share-cluster-picker-2-splits-placed")
        }
    }

    private func settle(_ window: UIWindow, seconds: TimeInterval = 0.5) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            // Sleeping rather than spinning the run loop: the sheet's
            // presentation and the composer's own `Task.sleep` both need the
            // main actor free, not held by this loop.
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private static func photograph(_ window: UIWindow, named name: String) throws {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("evidence: \(url.path())")
    }
}
