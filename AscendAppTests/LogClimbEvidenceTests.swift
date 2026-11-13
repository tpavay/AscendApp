import Foundation
import PhotosUI
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
        // A returning climber with a long Same as chip, which once stacked the chip row and pushed
        // the OPTIONAL chips under the keypad.
        let last = LastClimbPreset(date: Self.now.addingTimeInterval(-86_400), steps: 12_345, duration: 4_500)
        let viewModel = LogClimbViewModel(lastClimb: last, now: Self.now)
        Self.typed(viewModel, steps: "7500", time: "3000")

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let copy = try await screen.copy { $0.contains("over 220 steps a minute") }

            #expect(copy.contains("over 220 steps a minute. this climb will not count on leaderboards."), "\(copy)")
            #expect(viewModel.canSave(now: Self.now), "the climb is allowed to save")

            // The warning must not push the first row of OPTIONAL buttons under the keypad: the
            // scroll area ends 8 points above the keypad's first row, and a button past that line
            // is drawn cut in half. The second row is below the fold here and scrolls into reach.
            let texts = try await screen.texts()
            let firstKey = try #require(texts.first { $0.text == "1" }?.frame)
            let dateChip = try #require(texts.first { $0.text.hasPrefix("When: ") }?.frame)
            let sameAsChip = try #require(texts.first { $0.text.hasPrefix("Same as ") }?.frame)
            #expect(abs(sameAsChip.midY - dateChip.midY) < 1, "the Same as chip sits beside the date: \(dateChip) \(sameAsChip)")
            let firstRow = texts.filter { $0.text == "Add Effort" || $0.text == "Add Heart rate" }.map(\.frame)
            #expect(firstRow.count == 2, "\(texts.map(\.text))")
            for button in firstRow {
                #expect(button.maxY <= firstKey.minY - 8, "button \(button) runs under the keypad at \(firstKey)")
            }
            try screen.photograph(named: "log-climb-04-over-the-ceiling")
        }
    }

    /// A solid-colour picture standing in for a picked photo, so a hosted test can fill the
    /// PHOTOS row without the photo library.
    private static func pickedPhoto(_ color: UIColor) -> SelectedPhotoItem {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
        }
        return SelectedPhotoItem(
            pickerItem: PhotosPickerItem(itemIdentifier: UUID().uuidString),
            image: Image(uiImage: image),
            localIdentifier: UUID().uuidString
        )
    }

    @Test("Optional details start as a two by two grid of plus buttons")
    func theOptionalGridIsTwoByTwo() async throws {
        let viewModel = LogClimbViewModel(now: Self.now)
        Self.typed(viewModel, steps: "3200", time: "4000")
        viewModel.focusedField = .amount

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let texts = try await screen.texts { $0.contains { $0.text == "Add Photo" } }
            let frames = ["Add Effort", "Add Heart rate", "Add Note", "Add Photo"].map { label in
                texts.first { $0.text == label }?.frame
            }
            let effort = try #require(frames[0]), heartRate = try #require(frames[1])
            let note = try #require(frames[2]), photo = try #require(frames[3])

            #expect(abs(effort.midY - heartRate.midY) < 1, "Effort and Heart rate share a row")
            #expect(abs(note.midY - photo.midY) < 1, "Note and Photo share a row")
            #expect(note.minY > effort.maxY, "the second row sits under the first")
            #expect(abs(effort.minX - note.minX) < 1 && abs(heartRate.minX - photo.minX) < 1, "two columns")
            try screen.photograph(named: "log-climb-10-optional-grid")
        }
    }

    @Test("Effort and a note become cards, and the buttons left over close ranks")
    func effortAndNoteBecomeCards() async throws {
        let viewModel = LogClimbViewModel(now: Self.now)
        Self.typed(viewModel, steps: "3200", time: "4000")
        viewModel.details.effortRating = 3
        viewModel.details.note = "Legs were dead from Saturday, so I kept it steady. Machine 4 by the windows."
        viewModel.optionalInputFinished(now: Self.now)

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let copy = try await screen.copy { $0.contains("save climb") }

            for fragment in ["effort", "3 out of 5, moderate", "note", "legs were dead", "optional", "add heart rate", "add photo"] {
                #expect(copy.contains(fragment), "missing \"\(fragment)\" in: \(copy)")
            }
            #expect(!copy.contains("add effort") && !copy.contains("add note"), "filled details stop offering a plus: \(copy)")
            #expect(!copy.contains("avg heart rate"), "\(copy)")
            #expect(viewModel.focusedField == nil, "a climb that can save puts the keypad away")
            #expect(!copy.contains("delete"), "the keypad is gone: \(copy)")
            try screen.photograph(named: "log-climb-11-effort-and-note")
        }
    }

    @Test("Every detail filled: Effort beside Avg heart rate, the note, and a Photos row with its Add tile")
    func everyDetailFilled() async throws {
        let viewModel = LogClimbViewModel(now: Self.now)
        Self.typed(viewModel, steps: "3200", time: "4000")
        viewModel.details.effortRating = 3
        viewModel.details.averageHeartRate = 160
        viewModel.details.note = "Legs were dead from Saturday, so I kept it steady. Machine 4 by the windows."
        viewModel.selectedPhotos = [Self.pickedPhoto(.systemTeal)]
        viewModel.optionalInputFinished(now: Self.now)

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let texts = try await screen.texts { $0.contains { $0.text == "Add photo" } }
            let copy = texts.map(\.text).joined(separator: " | ").lowercased()

            for fragment in ["effort", "average heart rate", "note", "photos", "add photo", "remove media", "save climb"] {
                #expect(copy.contains(fragment), "missing \"\(fragment)\" in: \(copy)")
            }
            #expect(!copy.contains("optional"), "nothing left to offer: \(copy)")

            let effort = try #require(texts.first { $0.text.hasPrefix("Effort") }?.frame)
            let heartRate = try #require(texts.first { $0.text.hasPrefix("Average heart rate") }?.frame)
            #expect(abs(effort.midY - heartRate.midY) < 1 && heartRate.minX > effort.maxX, "the two cards sit side by side")

            let photo = try #require(texts.first { $0.text == "Photo" && abs($0.frame.width - $0.frame.height) < 1 }?.frame)
            let add = try #require(texts.first { $0.text == "Add photo" }?.frame)
            #expect(abs(photo.midY - add.midY) < 1 && add.minX > photo.maxX, "the Add tile follows the thumbnail inline")
            #expect(abs(photo.width - photo.height) < 1, "the thumbnail is square, never stretched: \(photo)")
            #expect(abs(add.width - photo.width) < 1 && abs(add.height - photo.height) < 1, "the Add tile matches it: \(add)")
            try screen.photograph(named: "log-climb-12-every-detail-filled")
        }
    }

    @Test("PHOTOS lines up with its thumbnails and with OPTIONAL below them")
    func thePhotosLabelSitsFlush() async throws {
        let viewModel = LogClimbViewModel(now: Self.now)
        Self.typed(viewModel, steps: "3200", time: "4000")
        viewModel.selectedPhotos = [Self.pickedPhoto(.systemTeal)]
        viewModel.optionalInputFinished(now: Self.now)

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(try Self.container())
        ) { screen in
            let texts = try await screen.texts { $0.contains { $0.text == "Add photo" } }
            let label = try #require(texts.first { $0.text.uppercased() == "PHOTOS" }?.frame)
            let photo = try #require(texts.first { $0.text == "Photo" && abs($0.frame.width - $0.frame.height) < 1 }?.frame)
            let optional = try #require(texts.first { $0.text.uppercased() == "OPTIONAL" }?.frame)

            #expect(abs(label.minX - photo.minX) < 1, "PHOTOS \(label) against its thumbnail \(photo)")
            #expect(abs(label.minX - optional.minX) < 1, "PHOTOS \(label) against OPTIONAL \(optional)")
        }
    }

    @Test("A save in flight shows a spinner a climber can see on the dark button")
    func theSaveSpinnerIsVisible() async throws {
        let held = AsyncStream<Void>.makeStream()
        let viewModel = LogClimbViewModel(now: Self.now, uploadMedia: { _ in
            for await _ in held.stream {}
            return []
        })
        Self.typed(viewModel, steps: "3200", time: "4000")
        viewModel.selectedPhotos = [Self.pickedPhoto(.systemTeal)]
        viewModel.optionalInputFinished(now: Self.now)
        let container = try Self.container()
        let context = ModelContext(container)

        try await RenderedScreen.host(
            LogClimbView(viewModel: viewModel)
                .environment(AuthenticationViewModel())
                .modelContainer(container)
        ) { screen in
            // Read while idle: the button does not move, and a running spinner keeps the
            // accessibility tree from settling.
            let button = try #require(try await screen.frame(ofElementLabelled: "Save climb"))

            let saving = Task { await viewModel.save(modelContext: context, now: Self.now) }
            defer { held.continuation.finish() }
            while !viewModel.isSaving {
                await Task.yield()
            }
            try await screen.settle()

            let center = CGRect(x: button.midX - 24, y: button.midY - 24, width: 48, height: 48)
            let brightest = try screen.withPixels(scale: 2) { pixels in
                pixels.pixels(in: center).map(\.luminance).max() ?? 0
            }
            try screen.photograph(named: "log-climb-13-save-in-flight")
            #expect(brightest > 60, "the spinner disappears into the button: brightest \(brightest)")

            held.continuation.finish()
            await saving.value
        }
    }

    @Test("The heart rate sheet is a big bpm field over the keypad, with Done as a link")
    func theHeartRateSheet() async throws {
        try await RenderedScreen.host(
            LogClimbHeartRateSheet(heartRate: .constant(160))
                .preferredColorScheme(.dark),
            size: CGSize(width: 402, height: 560)
        ) { screen in
            let copy = try await screen.copy { $0.contains("done") }

            for fragment in ["average heart rate", "160", "from your watch or the machine's grips.", "done", "delete"] {
                #expect(copy.contains(fragment), "missing \"\(fragment)\" in: \(copy)")
            }
            try screen.photograph(named: "log-climb-13-heart-rate-sheet")
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
            #expect(!copy.contains("logged by hand"), "the result screen is not the climb's detail: \(copy)")
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

            #expect(copy.contains("250 steps a minute is over the 220 limit"), "\(copy)")
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

    @Test("No leaderboard row says how its climbs were recorded")
    func noRowCarriesASourceMark() async throws {
        let origins: [ClimbOrigin] = [.live, .manual, .healthImport]

        try await RenderedScreen.host(
            VStack(spacing: 0) {
                ForEach(Array(origins.enumerated()), id: \.offset) { index, origin in
                    LeaderboardRow(
                        entry: .preview(
                            userId: "u\(index)",
                            displayName: "Climber \(index + 1)",
                            rank: index + 1,
                            value: Double(40_000 - index * 3_000),
                            formattedValue: (40_000 - index * 3_000).formatted(),
                            origin: origin
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
            let elements = try await screen.elements { $0.count >= 3 }
            let labels = elements.compactMap { ($0 as? NSObject)?.accessibilityLabel?.lowercased() }

            for spoken in ["recorded live", "logged by hand", "imported", "headphones", "pencil", "heart"] {
                #expect(
                    !labels.contains { $0.contains(spoken) },
                    "a row says \"\(spoken)\" - rows read: \(labels)"
                )
            }
            try screen.photograph(named: "log-climb-09-leaderboard-rows")
        }
    }

    @Test("A climb's detail ends with how it came to exist: Logged by hand or Imported from Apple Health, and nothing for a live climb")
    func theDetailFootnoteIsTheOnlyPlaceTheSourceShows() async throws {
        for (source, expected) in [
            (WorkoutSource.manual, "logged by hand"),
            (WorkoutSource.appleHealth, "imported from apple health"),
            (WorkoutSource.headphoneMotion, nil),
        ] as [(WorkoutSource, String?)] {
            let container = try Self.container()
            let workout = Workout(
                name: "Stair Stepper", date: Date(), duration: 1_800, steps: 3_000, floors: 150, source: source
            )
            container.mainContext.insert(workout)
            try container.mainContext.save()

            try await RenderedScreen.host(
                WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
                    .environment(AuthenticationViewModel())
                    .environment(MediaUploadManager.shared)
                    .modelContainer(container)
            ) { screen in
                let copy = try await screen.copy { $0.contains("3,000") }

                for phrase in ["logged by hand", "imported from apple health"] {
                    #expect(
                        copy.contains(phrase) == (phrase == expected),
                        "\(source.rawValue) detail should \(phrase == expected ? "" : "not ")say \"\(phrase)\": \(copy)"
                    )
                }
            }
        }
    }
}
