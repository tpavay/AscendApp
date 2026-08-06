import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Photographs the two sync surfaces `WorkoutSyncSurfaceEvidenceTests` cannot reach.
///
/// That suite renders `WorkoutSyncStatusRow` in isolation through `ImageRenderer`, which leaves two
/// gaps. The climbs list is where a climber first meets an unsynced climb, and its badge lives on
/// `WorkoutRowView` rather than on the row - so nothing pictures it. And `ImageRenderer` cannot
/// draw `ProgressView`, so the state a climber sees for the whole duration of a tap is the one
/// state with no honest picture of it.
///
/// Both are answered here by drawing through a live `UIWindow` instead: the same path UIKit uses
/// to put pixels on a screen, spinner included. Writes PNGs to `ASCEND_EVIDENCE_DIR`.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct WorkoutSyncListBadgeEvidenceTests {
    /// The climbs list, with one climb that reached the account and one that did not.
    ///
    /// Side by side on purpose: the badge's whole job is to make the second distinguishable from
    /// the first, and before this change the two rows were pixel-identical.
    @Test
    func capturesTheClimbsListBadge() throws {
        let container = try Self.hostedContainer()

        let synced = Self.makeWorkout(name: "CN Tower Live Climb", steps: 3_042)
        synced.markPendingRemoteUpsert(ownerUserId: "user-123")
        synced.markRemoteSyncSucceeded(heartRateSeries: nil)

        let unsynced = Self.makeWorkout(name: "Morning Stepper", steps: 1_884)
        unsynced.markPendingRemoteUpsert(ownerUserId: "user-123")
        unsynced.remoteSyncStatus = .rejected

        container.mainContext.insert(synced)
        container.mainContext.insert(unsynced)
        try container.mainContext.save()

        let list = VStack(spacing: 12) {
            WorkoutRowView(workout: synced, showsCouldNotSyncBadge: false)
            WorkoutRowView(workout: unsynced, showsCouldNotSyncBadge: true)
        }
        .padding(16)
        .modelContainer(container)

        try Self.capture(
            name: "07-list-couldnt-sync-badge",
            caption: "Climbs list: the second climb is not in the account, and now says so",
            content: list,
            height: 320
        )
    }

    /// The tapped state, drawn the way the device draws it.
    ///
    /// `WorkoutSyncSurfaceEvidenceTests` has to caption this state with an apology for the missing
    /// spinner. This is the same state with the spinner actually in it, so the reviewer can see
    /// that the warning text is unchanged from the untapped row rather than take it on trust.
    @Test
    func capturesTheTappedStateWithItsRealSpinner() throws {
        try Self.capture(
            name: "08-tapped-live-spinner",
            caption: "Tapped, drawn through UIKit: real spinner, and the warning has not moved",
            content: WorkoutSyncStatusRow(
                presentation: .couldNotSyncRetrying,
                effectiveColorScheme: .dark,
                onRetry: {}
            )
            .padding(.horizontal, 16),
            height: 120
        )
    }

    /// The section nested the way `WorkoutDetailView` actually nests it.
    ///
    /// `WorkoutSyncStatusSectionHostingTests` proves the hidden-to-warning transition works with
    /// the section as a hosting controller's *root* view. The detail screen does not place it
    /// there: `workoutContentSectionsWithoutTitle` puts it inside a `Group` inside a
    /// `VStack(spacing: 24)`, and that is the placement a climber's phone runs.
    ///
    /// The explicit-presentation control below is what makes a failure here diagnosable. If the
    /// control draws and the section does not, nesting is not suppressing the drawing - the section
    /// resolved its own presentation to nothing, and the warning the whole change exists to show is
    /// dead on the screen it ships on.
    @Test
    func theRowSurvivesTheDetailScreensNesting() async throws {
        let container = try Self.hostedContainer()

        let workout = Self.makeWorkout(name: "CN Tower Live Climb", steps: 3_042)
        workout.markPendingRemoteUpsert(ownerUserId: "user-123")
        workout.remoteSyncStatus = .rejected
        container.mainContext.insert(workout)
        try container.mainContext.save()

        #expect(
            WorkoutSyncCoordinator.shared.syncPresentation(
                for: workout,
                modelContext: container.mainContext
            ) == .couldNotSync,
            "the coordinator has to be offering a warning, or this test is measuring nothing"
        )

        func nested(@ViewBuilder middle: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 24) {
                Text("CN TOWER LIVE CLIMB")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)
                middle()
                Text("3,042 steps")
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(.white)
            }
            .frame(width: 402, alignment: .leading)
            .padding(16)
            .environment(AuthenticationViewModel())
            .modelContainer(container)
        }

        let withoutRow = try await Self.settledHeight(of: nested { EmptyView() })
        let withExplicitRow = try await Self.settledHeight(of: nested {
            WorkoutSyncStatusRow(presentation: .couldNotSync, effectiveColorScheme: .dark, onRetry: {})
        })
        let withSection = try await Self.settledHeight(of: nested {
            WorkoutSyncStatusSection(workout: workout, effectiveColorScheme: .dark)
        })

        #expect(
            withExplicitRow > withoutRow,
            "a row handed its presentation must draw here, or the harness cannot see any row at all"
        )
        #expect(
            withSection == withExplicitRow,
            """
            Nested as the detail screen nests it, the sync section is \(withSection)pt against \
            \(withExplicitRow)pt for the same row handed its presentation, and \(withoutRow)pt for \
            no row at all. The section resolved its presentation to nothing, so a climber whose \
            climb was refused sees no warning and no TRY AGAIN on the detail screen. Mounting the \
            section as a hosting controller's root view does not catch this; only nesting it the \
            way the screen nests it does.
            """
        )

        try await Self.captureAfterSettling(
            name: "09-detail-section-nested",
            caption: "Detail screen nesting: the row a climber should see on a refused climb",
            content: nested {
                WorkoutSyncStatusSection(workout: workout, effectiveColorScheme: .dark)
            },
            height: 220
        )
    }

    private static func settledHeight(of view: some View) async throws -> CGFloat {
        let host = UIHostingController(rootView: view)
        let window = try makeWindow(host: host, height: 874)
        defer { tearDown(window) }

        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(10))
            _ = intrinsicHeight(of: host, in: window)
        }
        return intrinsicHeight(of: host, in: window)
    }

    private static func makeWorkout(name: String, steps: Int) -> Workout {
        Workout(
            name: name,
            date: Date(timeIntervalSince1970: 1_780_000_000),
            duration: 2_347,
            steps: steps,
            floors: 190,
            stepsPerFloor: 16,
            notes: "",
            source: .manual
        )
    }

    private static func capture(
        name: String,
        caption: String,
        content: some View,
        height: CGFloat
    ) throws {
        let (window, image) = try hostAndDraw(caption: caption, content: content, height: height)
        defer { tearDown(window) }
        try write(image, name: name)
    }

    /// The lifecycle-driven variant: pumps the run loop until the section stops being empty.
    private static func captureAfterSettling(
        name: String,
        caption: String,
        content: some View,
        height: CGFloat
    ) async throws {
        let framed = frame(caption: caption, content: content, height: height)
        let host = UIHostingController(rootView: framed)
        let window = try makeWindow(host: host, height: height)
        defer { tearDown(window) }

        // Photographed after the lifecycle has had every chance to run, so the picture shows
        // whatever the screen genuinely settles on. The caller owns the verdict on whether that
        // is the right thing.
        var settledHeight = intrinsicHeight(of: host, in: window)
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(10))
            settledHeight = intrinsicHeight(of: host, in: window)
        }

        try write(draw(window, fittingHeight: settledHeight), name: name)
    }

    private static func intrinsicHeight(
        of host: UIHostingController<some View>,
        in window: UIWindow
    ) -> CGFloat {
        pump(window)
        return host.sizeThatFits(
            in: CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude)
        ).height
    }

    private static func hostAndDraw(
        caption: String,
        content: some View,
        height: CGFloat
    ) throws -> (UIWindow, UIImage) {
        let host = UIHostingController(rootView: frame(caption: caption, content: content, height: height))
        let window = try makeWindow(host: host, height: height)

        var fitted = height
        for _ in 0..<10 {
            fitted = intrinsicHeight(of: host, in: window)
        }

        return (window, draw(window, fittingHeight: fitted))
    }

    /// Kept out of any async context: `RunLoop.current` is unavailable from one, and the only way
    /// to let SwiftUI's lifecycle and UIKit's layout actually run is to turn the loop by hand.
    private static func pump(_ window: UIWindow) {
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())
    }

    private static func frame(
        caption: String,
        content: some View,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(20)
        .frame(width: 402, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private static func makeWindow(
        host: UIHostingController<some View>,
        height: CGFloat
    ) throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "test host app should expose a live UIWindowScene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
        window.rootViewController = host
        window.makeKeyAndVisible()
        return window
    }

    /// `layer.render(in:)` rather than `drawHierarchy`, because the latter needs a real screen
    /// update cycle the test host does not reliably get and returns blank when it does not.
    private static func draw(_ window: UIWindow, fittingHeight: CGFloat) -> UIImage {
        // Sized to the content rather than to a guess, so a row that appears cannot fall off the
        // bottom of its own evidence.
        window.frame = CGRect(x: 0, y: 0, width: 402, height: ceil(fittingHeight))
        pump(window)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    private static func tearDown(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
    }

    private static func write(_ image: UIImage, name: String) throws {
        guard let data = image.pngData() else {
            Issue.record("No PNG data for \(name)")
            return
        }

        let candidates = [
            ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"],
            NSTemporaryDirectory().appending("ascend-sync-surface-evidence")
        ].compactMap { $0 }

        for directory in candidates {
            let url = URL(filePath: directory).appending(path: "\(name).png")
            do {
                try FileManager.default.createDirectory(
                    at: URL(filePath: directory),
                    withIntermediateDirectories: true
                )
                try data.write(to: url)
                print("ASCEND_EVIDENCE_PNG \(url.path)")
                return
            } catch {
                continue
            }
        }
        Issue.record("No writable evidence directory for \(name)")
    }

    /// Held for the process for the same reason the hosting suite holds its own: SwiftUI keeps
    /// observing SwiftData for a beat after a host is torn down.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        WorkoutSyncOutboxEntry.self,
        PendingWorkoutDeletion.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    private static func hostedContainer() throws -> ModelContainer {
        try #require(container, "The evidence test needs an in-memory model container")
    }
}
