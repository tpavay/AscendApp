import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import Testing

@testable import AscendApp

/// What the Log a climb screen decides about its optional details and its keypad, with no view
/// in the way.
@MainActor
struct LogClimbOptionalDetailsTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static func typed(steps: String, time: String) -> LogClimbViewModel {
        let viewModel = LogClimbViewModel(now: now)
        viewModel.focusedField = .amount
        steps.compactMap(\.wholeNumberValue).forEach { viewModel.press(digit: $0) }
        viewModel.focusedField = .time
        time.compactMap(\.wholeNumberValue).forEach { viewModel.press(digit: $0) }
        return viewModel
    }

    private static func pickedPhoto() -> SelectedPhotoItem {
        SelectedPhotoItem(
            pickerItem: PhotosPickerItem(itemIdentifier: UUID().uuidString),
            image: Image(systemName: "photo"),
            localIdentifier: UUID().uuidString
        )
    }

    private static func pickedVideo() throws -> SelectedPhotoItem {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data([0]).write(to: url)
        return SelectedPhotoItem(
            pickerItem: PhotosPickerItem(itemIdentifier: UUID().uuidString),
            image: Image(systemName: "video"),
            localIdentifier: UUID().uuidString,
            isVideo: true,
            duration: 10,
            videoURL: url
        )
    }

    private static func fileExists(for item: SelectedPhotoItem) throws -> Bool {
        FileManager.default.fileExists(atPath: try #require(item.videoURL).path(percentEncoded: false))
    }

    private static func context() throws -> ModelContext {
        ModelContext(
            try RetainedModelContainer.inMemory(
                for: Workout.self,
                WorkoutSourceLink.self,
                WorkoutParticipation.self,
                LeaderboardStats.self,
                BestEffortCacheEntry.self,
                BestEffortCacheMetadata.self
            )
        )
    }

    @Test("A fresh form offers all four details, in the order the grid draws them")
    func allFourStartUnfilled() {
        let viewModel = LogClimbViewModel(now: Self.now)

        #expect(viewModel.unfilledOptionalFields == [.effort, .heartRate, .note, .photo])
        #expect(viewModel.optionalFieldCount == 0)
    }

    @Test("A detail that is filled stops being offered, and a blank note does not count as filled")
    func filledDetailsLeaveTheGrid() {
        let viewModel = LogClimbViewModel(now: Self.now)
        viewModel.details.effortRating = 3
        viewModel.details.note = "   \n"
        viewModel.details.averageHeartRate = 160

        #expect(viewModel.unfilledOptionalFields == [.note, .photo])
        #expect(viewModel.isFilled(.effort) && viewModel.isFilled(.heartRate))
        #expect(!viewModel.isFilled(.note))
    }

    @Test("Once steps and time can save, closing an optional input puts the keypad away")
    func keypadStepsAsideWhenTheClimbCanSave() {
        let viewModel = Self.typed(steps: "3200", time: "4000")

        viewModel.optionalInputFinished(now: Self.now)

        #expect(viewModel.focusedField == nil)
        viewModel.press(digit: 9)
        #expect(viewModel.amountDisplay == "3,200", "no field is typing, so the keypad changes nothing")
        #expect(viewModel.timeDisplay == "40:00")
    }

    @Test("While a number is missing or refused, the keypad stays")
    func keypadStaysWhileANumberIsMissing() {
        let incomplete = LogClimbViewModel(now: Self.now)
        incomplete.optionalInputFinished(now: Self.now)
        #expect(incomplete.focusedField == .amount)

        let refused = Self.typed(steps: "49120", time: "4000")
        refused.optionalInputFinished(now: Self.now)
        #expect(refused.focusedField == .time)
    }

    @Test("A lone photo has nothing to highlight")
    func aLonePhotoCannotBeHighlighted() {
        let viewModel = LogClimbViewModel(now: Self.now)
        let photo = Self.pickedPhoto()
        viewModel.selectedPhotos = [photo]

        viewModel.highlightPhoto(id: photo.id)

        #expect(viewModel.highlightedPhotoId == nil)
    }

    @Test("With two photos one can be highlighted, and a second tap takes it back")
    func aSecondTapClearsTheHighlight() {
        let viewModel = LogClimbViewModel(now: Self.now)
        let first = Self.pickedPhoto()
        viewModel.selectedPhotos = [first, Self.pickedPhoto()]

        viewModel.highlightPhoto(id: first.id)
        #expect(viewModel.highlightedPhotoId == first.id)

        viewModel.highlightPhoto(id: first.id)
        #expect(viewModel.highlightedPhotoId == nil)
    }

    @Test("Removing the highlighted photo clears the highlight, and removing another keeps it")
    func removingTheHighlightedPhotoClearsIt() {
        let viewModel = LogClimbViewModel(now: Self.now)
        let highlighted = Self.pickedPhoto()
        let other = Self.pickedPhoto()
        let third = Self.pickedPhoto()
        viewModel.selectedPhotos = [highlighted, other, third]
        viewModel.highlightPhoto(id: highlighted.id)

        viewModel.removePhoto(id: other.id)
        #expect(viewModel.highlightedPhotoId == highlighted.id)

        viewModel.removePhoto(id: highlighted.id)
        #expect(viewModel.highlightedPhotoId == nil)
        #expect(viewModel.selectedPhotos.map(\.id) == [third.id])
    }

    @Test("Save and the picker both wait while a pick is being prepared, then the pick is on the climb")
    func saveWaitsForAPickBeingPrepared() {
        let viewModel = Self.typed(steps: "3200", time: "4000")
        #expect(viewModel.canSave(now: Self.now))
        #expect(viewModel.canPickMedia)

        viewModel.mediaPreparationDidStart()
        #expect(!viewModel.canSave(now: Self.now))
        #expect(!viewModel.canPickMedia)

        viewModel.mediaPreparationDidFinish(adding: [Self.pickedPhoto()])
        #expect(viewModel.canSave(now: Self.now))
        #expect(viewModel.canPickMedia)
        #expect(viewModel.selectedPhotos.count == 1)
    }

    @Test("Save refuses to run while a pick is being prepared")
    func saveDoesNothingWhileAPickIsBeingPrepared() async throws {
        let viewModel = Self.typed(steps: "3200", time: "4000")
        viewModel.mediaPreparationDidStart()

        await viewModel.save(modelContext: try Self.context(), now: Self.now)

        #expect(viewModel.savedWorkout == nil)
    }

    @Test("A video that finishes preparing after the climb saved has its temp file removed")
    func aPickArrivingAfterSaveIsCleanedUp() async throws {
        let viewModel = Self.typed(steps: "3200", time: "4000")
        await viewModel.save(modelContext: try Self.context(), now: Self.now)
        try #require(viewModel.savedWorkout != nil)
        let late = try Self.pickedVideo()

        viewModel.mediaPreparationDidFinish(adding: [late])

        #expect(viewModel.selectedPhotos.isEmpty)
        #expect(try !Self.fileExists(for: late))
        #expect(viewModel.canPickMedia)
    }

    @Test("A video that finishes preparing after the screen closed has its temp file removed")
    func aPickArrivingAfterCloseIsCleanedUp() throws {
        let viewModel = Self.typed(steps: "3200", time: "4000")
        viewModel.mediaPreparationDidStart()
        viewModel.close()
        let late = try Self.pickedVideo()

        viewModel.mediaPreparationDidFinish(adding: [late])

        #expect(viewModel.selectedPhotos.isEmpty)
        #expect(try !Self.fileExists(for: late))
    }

    @Test("Closing the screen removes the temp file of a video already on the climb")
    func closingRemovesWhatWasPicked() throws {
        let viewModel = Self.typed(steps: "3200", time: "4000")
        let picked = try Self.pickedVideo()
        viewModel.mediaPreparationDidFinish(adding: [picked])
        #expect(try Self.fileExists(for: picked))

        viewModel.close()

        #expect(viewModel.selectedPhotos.isEmpty)
        #expect(try !Self.fileExists(for: picked))
    }

    @Test("The picker and the card it fills name each level with the same five words")
    func effortWords() {
        #expect((1...5).map(EffortRatingView.effortWord) == ["Minimal", "Light", "Moderate", "High", "Maximum"])
    }
}
