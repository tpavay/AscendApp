import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Mounts the sync row on a live window and measures what it actually draws.
///
/// Rendering `WorkoutSyncStatusRow` with an explicit presentation, as the evidence test does, only
/// ever proves the row can draw. These mount `WorkoutSyncStatusSection` - the thing the detail
/// screen places - through `RenderedScreen` and check the two states that decide whether a
/// climber ever sees the warning: a refused climb has to occupy space, and a clean one has to
/// occupy none.
///
/// `WorkoutSyncListBadgeEvidenceTests.theRowSurvivesTheDetailScreensNesting` is the companion that
/// nests the section inside a stack rather than mounting it as a root view.
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

        let height = try await RenderedScreen.host(host) { screen -> CGFloat in
            var height = Self.measuredHeight(of: host, in: screen.window)
            for _ in 0..<60 where height == 0 {
                try await Task.sleep(for: .milliseconds(10))
                height = Self.measuredHeight(of: host, in: screen.window)
            }
            return height
        }

        #expect(
            height > 0,
            """
            The sync row drew nothing for a climb the cloud refused, so the warning - and the TRY \
            AGAIN control with it - is dead on this screen.
            """
        )
    }

    /// The constraint that rules out a permanently present container for the row.
    ///
    /// Giving the section an always-drawing anchor - a zero-size `Color.clear` in a `ZStack` -
    /// would make it a real layout subview even with nothing to say, and the detail screen stacks
    /// it at `spacing: 24`. Every climb that synced cleanly would then carry a phantom gap where
    /// the row is not. Only a genuinely empty body is elided from a stack, so the row renders
    /// nothing when there is nothing to say, and the test above is what proves it still draws when
    /// there is.
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

        // One screen at a time: the host has a single window scene to lend.
        let withRowHeight = try await Self.hostedHeight(of: withRow)
        let withoutRowHeight = try await Self.hostedHeight(of: withoutRow)

        #expect(
            withRowHeight == withoutRowHeight,
            """
            A climb that synced cleanly is paying \(withRowHeight - withoutRowHeight)pt for a row \
            it does not show. The hidden row has stopped being elided from the stack.
            """
        )
    }

    private static func hostedHeight(of view: some View) async throws -> CGFloat {
        let host = UIHostingController(rootView: view)
        return try await RenderedScreen.host(host) { screen -> CGFloat in
            var height = measuredHeight(of: host, in: screen.window)
            for _ in 0..<10 {
                height = measuredHeight(of: host, in: screen.window)
            }
            return height
        }
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
