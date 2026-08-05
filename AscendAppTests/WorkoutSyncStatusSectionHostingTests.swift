import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Mounts the sync row the way the detail screen does, on a live window.
///
/// The row starts at `.hidden` and renders nothing in that state, and the only things that can move
/// it off `.hidden` are lifecycle modifiers. So the surface is only alive if those modifiers fire
/// for a view that is producing no output at the moment they would run - which is the shape SwiftUI
/// famously does not honour for `EmptyView`. Nothing short of hosting it can answer that: rendering
/// `WorkoutSyncStatusRow` with an explicit presentation, as the evidence test does, never exercises
/// the transition at all.
///
/// Hidden-to-warning is the transition that matters, because it is the path a climber's first
/// failed climb takes.
@MainActor
@Suite(.hostsAWindow)
struct WorkoutSyncStatusSectionHostingTests {
    @Test
    func theRowResolvesFromItsHiddenInitialStateOnceMounted() async throws {
        let container = try Self.hostedContainer()

        let workout = Workout(
            name: "CN Tower Live Climb",
            date: Date(timeIntervalSince1970: 1_780_000_000),
            duration: 1_800,
            steps: 1_200,
            floors: 75,
            stepsPerFloor: 16,
            notes: "",
            source: .manual
        )
        workout.markPendingRemoteUpsert(ownerUserId: "user-123")
        // The state a climb reaches once its automatic series has stopped, which is exactly when
        // the row has something to say.
        workout.remoteSyncStatus = .rejected
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let host = UIHostingController(
            rootView: WorkoutSyncStatusSection(
                workout: workout,
                effectiveColorScheme: .dark
            )
            .environment(AuthenticationViewModel())
            .modelContainer(container)
        )

        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "test host app should expose a live UIWindowScene"
        )
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
            window.rootViewController = nil
            window.windowScene = nil
        }

        var height = Self.measuredHeight(of: host, in: window)
        for _ in 0..<60 where height == 0 {
            try await Task.sleep(for: .milliseconds(10))
            height = Self.measuredHeight(of: host, in: window)
        }

        #expect(
            height > 0,
            """
            The sync row never left its hidden initial state. Its lifecycle is attached to a view \
            that renders nothing until the lifecycle runs, so the row - and the TRY AGAIN control \
            with it - is dead on this screen.
            """
        )
    }

    /// The constraint that rules out the obvious way to make the lifecycle above unconditional.
    ///
    /// Anchoring the row's `.task` to an always-drawing sibling - a zero-size `Color.clear` in a
    /// `ZStack` - would make the section a real layout subview even with nothing to say, and the
    /// detail screen stacks it at `spacing: 24`. Every climb that synced cleanly would then carry
    /// a phantom gap where the row is not. Only a genuinely empty body is elided from a stack, so
    /// the row has to render nothing, and the hosting test above is what proves it still wakes up.
    @Test
    func aHiddenRowCostsNoStackSpacing() async throws {
        let container = try Self.hostedContainer()

        let synced = Workout(
            name: "Quiet Climb",
            date: Date(timeIntervalSince1970: 1_780_000_000),
            duration: 1_800,
            steps: 1_200,
            floors: 75,
            stepsPerFloor: 16,
            notes: "",
            source: .manual
        )
        synced.markPendingRemoteUpsert(ownerUserId: "user-123")
        synced.markRemoteSyncSucceeded(heartRateSeries: nil)
        container.mainContext.insert(synced)
        try container.mainContext.save()

        let withRow = VStack(spacing: 24) {
            Text("above")
            WorkoutSyncStatusSection(workout: synced, effectiveColorScheme: .dark)
            Text("below")
        }
        .environment(AuthenticationViewModel())
        .modelContainer(container)

        let withoutRow = VStack(spacing: 24) {
            Text("above")
            Text("below")
        }

        let (withRowHeight, window) = try Self.hostedHeight(of: withRow)
        defer { Self.tearDown(window) }

        let (withoutRowHeight, baselineWindow) = try Self.hostedHeight(of: withoutRow)
        defer { Self.tearDown(baselineWindow) }

        #expect(
            withRowHeight == withoutRowHeight,
            """
            A climb that synced cleanly is paying \(withRowHeight - withoutRowHeight)pt for a row \
            it does not show. The hidden row has stopped being elided from the stack.
            """
        )
    }

    private static func hostedHeight(of view: some View) throws -> (CGFloat, UIWindow) {
        let host = UIHostingController(rootView: view)
        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "test host app should expose a live UIWindowScene"
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()

        var height = measuredHeight(of: host, in: window)
        for _ in 0..<10 {
            height = measuredHeight(of: host, in: window)
        }
        return (height, window)
    }

    private static func tearDown(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
    }

    private static func measuredHeight(of host: UIHostingController<some View>, in window: UIWindow) -> CGFloat {
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())

        return host.sizeThatFits(
            in: CGSize(width: 402, height: CGFloat.greatestFiniteMagnitude)
        ).height
    }

    /// Held for the process rather than built per test: SwiftUI keeps observing SwiftData for a
    /// beat after a host is torn down, and a container that dies first traps the next save any
    /// suite performs.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        WorkoutSyncOutboxEntry.self,
        PendingWorkoutDeletion.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    private static func hostedContainer() throws -> ModelContainer {
        try #require(container, "The hosting test needs an in-memory model container")
    }
}
