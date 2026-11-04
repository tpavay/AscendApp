import Foundation
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

    @Test("Removing the highlighted photo clears the highlight, and a lone photo has nothing to highlight")
    func removingAndHighlightingPhotos() {
        let viewModel = LogClimbViewModel(now: Self.now)

        #expect(viewModel.canAddMorePhotos)
        #expect(viewModel.remainingPhotoSlots == SelectedMediaPreparationService.maximumMediaCount)
        #expect(viewModel.photoLimitContext.mediaCount == 0)

        viewModel.removePhoto(id: UUID())
        viewModel.highlightPhoto(id: UUID())
        #expect(viewModel.highlightedPhotoId == nil)
    }
}
