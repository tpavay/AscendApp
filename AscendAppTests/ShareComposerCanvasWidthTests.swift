import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The composer canvas used to letterbox on every device (#585): `canvasRegion`'s
/// `GeometryReader` was reduced by `bottomBar`'s own row before fitting the 9:19.5
/// story format, so the canvas always came out narrower than the screen - worst on
/// the smallest device. `bottomBar` now floats over the canvas's bottom edge
/// instead of reserving a row below it, so the canvas fits against the composer's
/// full height.
///
/// Measured the same way the bug itself was found: geometrically, off `topChrome`'s
/// own accessibility frames (its two circle buttons sit inside the same
/// `.frame(width: canvasSize.width, ...)` ZStack as the canvas, each inset by the
/// HStack's fixed 12pt padding), never by pixel-color sampling - so a background
/// photo that has not finished loading cannot skew the result.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareComposerCanvasWidthTests {

    /// The common case: every current non-SE iPhone's own aspect ratio is already
    /// almost exactly 9:19.5, so the fix should fill nearly the whole screen.
    @Test
    func canvasFillsNearlyTheFullWidthOnAModernIPhone() async throws {
        try await measure(name: "iphone-16-pro", size: CGSize(width: 393, height: 852)) { fillFraction in
            #expect(
                fillFraction > 0.95,
                "expected the canvas to fill more than 95% of the screen width on a modern iPhone, got \(fillFraction)"
            )
        }
    }

    /// The worst case: SE-class screens are proportionally wider/shorter than
    /// 9:19.5, so they can never reach 100% - but the fix still has to measurably
    /// beat the pre-fix 73.5%, not just move the letterboxing somewhere else.
    @Test
    func canvasFillsMoreOfTheWidthOnIPhoneSEThanBeforeTheFix() async throws {
        try await measure(name: "iphone-se", size: CGSize(width: 375, height: 667)) { fillFraction in
            #expect(
                fillFraction > 0.78,
                "expected the canvas to fill more than 78% of the screen width even on the shortest supported device (73.5% before the fix), got \(fillFraction)"
            )
        }
    }

    // MARK: - Shared hosting + measurement

    private func measure(
        name: String,
        size: CGSize,
        _ assertFillFraction: (Double) -> Void
    ) async throws {
        let defaultsSuite = "ShareComposerCanvasWidthTests-\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let walkthroughStore = ShareComposerWalkthroughStore(defaults: defaults)
        walkthroughStore.markSeen()

        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Live Climb",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true
        )
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let composer = ShareComposerView(
            workout: workout,
            climb: .preview,
            climbRank: 4,
            climbRankTotal: 1_284,
            walkthroughStore: walkthroughStore
        )
        .modelContainer(container)

        try await RenderedScreen.host(composer, size: size) { screen in
            _ = try await screen.elements()

            // Pick the climb's own hero photo as the background, exactly the
            // reported flow - the auto-opening add-stats sheet fires 0.35s later,
            // so settle briefly to read the bare canvas before it covers it.
            try activateAccessibilityElement(labelled: "Presets", in: screen.window)
            try await screen.settle(.turns(10))
            try activateAccessibilityElement(in: screen.window) {
                $0.accessibilityLabel == Climb.preview.name && $0.accessibilityTraits.contains(.button)
            }
            try await screen.settle(.turns(4))

            let chevron = try #require(
                try await screen.frame(ofElementLabelled: "Choose another background"),
                "topChrome's back chevron never appeared"
            )
            let filters = try #require(
                try await screen.frame(ofElementLabelled: "Background filters"),
                "topChrome's filters button never appeared"
            )
            let topChromeHorizontalPadding: CGFloat = 12
            let canvasWidth = (filters.maxX + topChromeHorizontalPadding) - (chevron.minX - topChromeHorizontalPadding)
            assertFillFraction(canvasWidth / size.width)

            // The add-pill is pure editing chrome (never exported) and now floats
            // above `bottomBar`'s own row instead of behind it - guard that the
            // two never overlap, or the pill's tap target would be stolen by
            // whichever button sits underneath it.
            let addPillFrame = try #require(
                try await screen.frame(ofElementLabelled: "Add stats"),
                "the add-stats pill never appeared"
            )
            let saveButtonFrame = try #require(
                try await screen.frame(ofElementLabelled: "SAVE"),
                "bottomBar's SAVE button never appeared"
            )
            #expect(
                addPillFrame.maxY <= saveButtonFrame.minY,
                "the add-stats pill overlaps bottomBar's own row: pill=\(addPillFrame) save=\(saveButtonFrame)"
            )
        }
    }
}
