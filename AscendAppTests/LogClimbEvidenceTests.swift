import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Reviewer-facing proof of the Log a climb screens: every state a climber can type the form
/// into, the result they land on, the climb it leaves behind, and the row that carries it.
///
/// Each surface is the shipped view hosted through `RenderedScreen`, and copy is read back off the
/// accessibility tree. Photographs are written to `ASCEND_EVIDENCE_DIR` when it is set.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LogClimbEvidenceTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static func container() throws -> ModelContainer {
        try RetainedModelContainer.inMemory(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        )
    }

    private static func typed(
        _ viewModel: LogClimbViewModel,
        steps: String,
        time: String
    ) {
        viewModel.focusedField = .amount
        steps.compactMap(\.wholeNumberValue).forEach { viewModel.press(digit: $0) }
        viewModel.focusedField = .time
        time.compactMap(\.wholeNumberValue).forEach { viewModel.press(digit: $0) }
    }

    @Test("The form opens empty, with Save waiting and every way in one tap away")
    func theFormOpensEmpty() async throws {
        let last = LastClimbPreset(date: Self.now.addingTimeInterval(-86_400), steps: 3_836, duration: 2_400)

        try await RenderedScreen.host(
            LogClimbView(lastClimb: last)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let copy = try await screen.copy { $0.contains("save climb") }

            for fragment in [
                "log a climb", "today · now", "same as", "3,836", "40 min", "steps", "floors",
                "time", "from the console", "optional", "effort", "heart rate", "note", "photo",
                "save climb"
            ] {
                #expect(copy.contains(fragment), "missing \"\(fragment)\" in: \(copy)")
            }
            #expect(!copy.contains("steps a minute"), "an empty form accuses nobody of anything")
            try screen.photograph(named: "log-climb-01-empty")
        }
    }

    @Test("A climb typed in reads back, and the same-as chip fills both numbers")
    func aTypedClimbReadsBack() async throws {
        let last = LastClimbPreset(date: Self.now.addingTimeInterval(-86_400), steps: 3_836, duration: 2_400)
        let viewModel = LogClimbViewModel(lastClimb: last, now: Self.now)
        viewModel.applyLastClimb()

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let copy = try await screen.copy { $0.contains("3,836") }

            #expect(copy.contains("3,836"))
            #expect(copy.contains("40:00"))
            #expect(viewModel.canSave(now: Self.now))
            try screen.photograph(named: "log-climb-02-filled-from-last")
        }
    }

    @Test("An impossible pace is refused inline with the mock's own sentence")
    func anImpossiblePaceIsRefused() async throws {
        let viewModel = LogClimbViewModel(now: Self.now)
        Self.typed(viewModel, steps: "49120", time: "4000")

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let copy = try await screen.copy { $0.contains("1,228") }

            #expect(copy.contains("that's 1,228 steps a minute. check the steps or time."), "\(copy)")
            #expect(!viewModel.canSave(now: Self.now), "Save stays disabled")
            try screen.photograph(named: "log-climb-03-refused")
        }
    }

    @Test("A pace between the ceiling and the line says the climb saves and stays off the boards")
    func aPaceOverTheCeilingSaysSo() async throws {
        let viewModel = LogClimbViewModel(now: Self.now)
        Self.typed(viewModel, steps: "7500", time: "3000")

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let copy = try await screen.copy { $0.contains("over 200 steps a minute") }

            #expect(copy.contains("over 200 steps a minute. this climb will not count on leaderboards."), "\(copy)")
            #expect(viewModel.canSave(now: Self.now), "the climb is allowed to save")

            // The warning must not push the OPTIONAL chips under the keypad: the scroll area ends
            // 8 points above the keypad's first row, and a chip past that line is drawn cut in half.
            let texts = try await screen.texts()
            let firstKey = try #require(texts.first { $0.text == "1" }?.frame)
            let chips = texts.filter { $0.text.hasPrefix("Add ") }.map(\.frame)
            #expect(chips.count == 4, "\(texts.map(\.text))")
            for chip in chips {
                #expect(chip.maxY <= firstKey.minY - 8, "chip \(chip) runs under the keypad at \(firstKey)")
            }
            try screen.photograph(named: "log-climb-04-over-the-ceiling")
        }
    }

    @Test("The Climb sheet offers Log it under ALREADY CLIMBED?")
    func theClimbSheetOffersLogIt() async throws {
        try await RenderedScreen.host(
            HomeStartActionSheet(onSelect: { _ in }, onLogIt: {})
                .frame(width: 402)
                .background(Color.black),
            size: CGSize(width: 402, height: 600)
        ) { screen in
            let copy = try await screen.copy { $0.contains("already climbed") }

            #expect(copy.contains("already climbed?"))
            #expect(copy.contains("log it"))
            #expect(copy.contains("just climb"))
            try screen.photograph(named: "log-climb-05-climb-sheet")
        }
    }

    @Test("The result of a climb that ranks, and of one the check kept off the boards")
    func theResultScreens() async throws {
        let container = try Self.container()

        let ranked = Workout(
            name: "Stair Stepper", date: Date(), duration: 2_400, steps: 3_200, floors: 200, source: .manual
        )
        let offTheBoards = Workout(
            name: "Stair Stepper", date: Date(), duration: 1_800, steps: 7_500, floors: 469, source: .manual
        )
        offTheBoards.refreshLeaderboardStatus()
        container.mainContext.insert(ranked)
        container.mainContext.insert(offTheBoards)
        try container.mainContext.save()

        try await RenderedScreen.host(
            LoggedClimbResultView(workout: ranked, onDone: {})
                .environment(AuthenticationViewModel())
                .modelContainer(container)
        ) { screen in
            let copy = try await screen.copy { $0.contains("total steps") }

            #expect(copy.contains("3,200"))
            #expect(copy.contains("40:00"))
            #expect(copy.contains("logged by hand"))
            #expect(copy.contains("share"))
            #expect(copy.contains("done"))
            #expect(!copy.contains("off the leaderboards"))
            try screen.photograph(named: "log-climb-06-result-ranked")
        }

        try await RenderedScreen.host(
            LoggedClimbResultView(workout: offTheBoards, onDone: {})
                .environment(AuthenticationViewModel())
                .modelContainer(container)
        ) { screen in
            let copy = try await screen.copy { $0.contains("off the leaderboards") }

            #expect(copy.contains("250 steps a minute is over the 200 limit"), "\(copy)")
            #expect(copy.contains("edit the steps or time and it ranks"), "\(copy)")
            try screen.photograph(named: "log-climb-07-result-off-the-boards")
        }
    }

    @Test("A climb with no steps shows a dash and an Add steps prompt")
    func aClimbWithNoStepsPromptsForThem() async throws {
        let container = try Self.container()
        let workout = Workout(
            name: "Stair Stepper", date: Date(), duration: 2_472, steps: 0, floors: 0, source: .manual
        )
        container.mainContext.insert(workout)
        try container.mainContext.save()

        try await RenderedScreen.host(
            WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
                .environment(AuthenticationViewModel())
                .environment(MediaUploadManager.shared)
                .modelContainer(container)
        ) { screen in
            let copy = try await screen.copy { $0.contains("add steps") }

            #expect(copy.contains("add steps"), "\(copy)")
            #expect(copy.contains("logged by hand"), "\(copy)")
            try screen.photograph(named: "log-climb-08-detail-no-steps")
        }
    }

    @Test("Every leaderboard row names how its climbs were recorded")
    func everyRowCarriesItsSourceIcon() async throws {
        let rows: [(ClimbOrigin, String)] = [
            (.live, "recorded live"),
            (.manual, "logged by hand")
        ]

        try await RenderedScreen.host(
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    LeaderboardRow(
                        entry: .preview(
                            userId: "u\(index)",
                            displayName: "Climber \(index + 1)",
                            rank: index + 1,
                            value: Double(40_000 - index * 3_000),
                            formattedValue: (40_000 - index * 3_000).formatted(),
                            origin: row.0
                        ),
                        metric: .climb
                    )
                }
            }
            .padding(.horizontal, 20)
            .frame(width: 402)
            .background(Color.black),
            size: CGSize(width: 402, height: 260)
        ) { screen in
            let elements = try await screen.elements { $0.count >= 2 }
            let labels = elements.compactMap { ($0 as? NSObject)?.accessibilityLabel?.lowercased() }

            for (_, spoken) in rows {
                #expect(
                    labels.contains { $0.contains(spoken) },
                    "no row says \"\(spoken)\" - rows read: \(labels)"
                )
            }
            try screen.photograph(named: "log-climb-09-leaderboard-rows")
        }
    }
}
