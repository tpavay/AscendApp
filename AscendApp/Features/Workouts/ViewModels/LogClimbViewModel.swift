import Foundation
import Observation
import SwiftData

/// The last climb a climber saved, as the "Same as" chip offers it back.
struct LastClimbPreset: Equatable, Sendable {
    let date: Date
    let steps: Int
    let duration: TimeInterval

    /// Built from a climb the climber already has, or nil when it carries no steps to repeat.
    init?(workout: Workout) {
        guard let steps = workout.recordedSteps, steps > 0, workout.duration > 0 else { return nil }
        date = workout.date
        self.steps = steps
        duration = workout.duration
    }

    init(date: Date, steps: Int, duration: TimeInterval) {
        self.date = date
        self.steps = steps
        self.duration = duration
    }

    /// `Same as Tue · 3,836 · 40 min`.
    func chipTitle(calendar: Calendar = .current, now: Date = Date()) -> String {
        let day = calendar.isDate(date, inSameDayAs: now)
            ? "today"
            : date.formatted(.dateTime.weekday(.abbreviated))
        return "Same as \(day) · \(steps.formatted()) · \(Self.durationPhrase(duration))"
    }

    static func durationPhrase(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int((duration / 60).rounded()), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        guard hours > 0 else { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }
}

/// The four details a climb can carry beyond steps and time, in the order the plus buttons show.
enum LogClimbOptionalField: CaseIterable, Identifiable {
    case effort
    case heartRate
    case note
    case photo

    var id: Self { self }

    var title: String {
        switch self {
        case .effort: "Effort"
        case .heartRate: "Heart rate"
        case .note: "Note"
        case .photo: "Photo"
        }
    }
}

/// UI state for the Log a climb screen.
///
/// Holds what the climber has typed and decides, through `LoggedClimbValidation`, what Save may
/// do. Nothing here knows about SwiftUI: the keypad calls `press`, the screen reads the rest.
@MainActor
@Observable
final class LogClimbViewModel {
    enum Field: Equatable {
        case amount
        case time
    }

    private(set) var input: LoggedClimbInput
    /// The number the keypad is typing into, or nil once the climber has stepped away from both -
    /// which is when the keypad gives its room back to what they added.
    var focusedField: Field? = .amount
    var details = LoggedClimbDetails()
    var selectedPhotos: [SelectedPhotoItem] = []
    var highlightedPhotoId: UUID?
    private(set) var isLoadingMedia = false
    private(set) var isSaving = false
    private(set) var saveErrorMessage: String?
    private(set) var savedWorkout: Workout?

    let lastClimb: LastClimbPreset?
    private let photoService = PhotoService()
    private var usedSameAsLast = false
    private var changedDate = false

    init(lastClimb: LastClimbPreset? = nil, now: Date = Date()) {
        self.lastClimb = lastClimb
        self.input = LoggedClimbInput(date: now)
    }

    // MARK: - What the screen reads

    func validation(now: Date = Date()) -> LoggedClimbValidation {
        LoggedClimbValidation.validate(input, now: now)
    }

    func canSave(now: Date = Date()) -> Bool {
        guard !isSaving else { return false }
        if case .ready = validation(now: now) { return true }
        return false
    }

    var unit: LoggedClimbInput.Unit { input.unit }

    /// The big number: `3,200`, or empty while nothing is typed.
    var amountDisplay: String {
        input.amount.map { $0.formatted() } ?? ""
    }

    var timeDisplay: String { input.timeEntry.display }

    var isTimeEmpty: Bool { input.timeEntry.isEmpty }

    var date: Date { input.date }

    /// `Today · now` until the climber picks something else, then `Today · 6:10 PM` or `Tue · 6:10 PM`.
    func dateChipTitle(calendar: Calendar = .current, now: Date = Date()) -> String {
        if !changedDate { return "Today · now" }
        let day = calendar.isDate(input.date, inSameDayAs: now)
            ? "Today"
            : input.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day) · \(input.date.formatted(date: .omitted, time: .shortened))"
    }

    /// The optional details the climber has not added yet, in the order the plus buttons show them.
    var unfilledOptionalFields: [LogClimbOptionalField] {
        LogClimbOptionalField.allCases.filter { !isFilled($0) }
    }

    func isFilled(_ field: LogClimbOptionalField) -> Bool {
        switch field {
        case .effort: details.effortRating != nil
        case .heartRate: details.averageHeartRate != nil
        case .note: !details.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .photo: !selectedPhotos.isEmpty
        }
    }

    var optionalFieldCount: Int {
        var count = 0
        if details.effortRating != nil { count += 1 }
        if details.averageHeartRate != nil { count += 1 }
        if !details.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !selectedPhotos.isEmpty { count += 1 }
        return count
    }

    // MARK: - Keypad

    /// Called when an optional input closes. Once steps and time make a climb that can save, the
    /// keypad has nothing left to type and steps aside; while either is missing or refused it
    /// stays, because the climber still has to fix a number.
    func optionalInputFinished(now: Date = Date()) {
        if case .ready = validation(now: now) {
            focusedField = nil
        }
    }

    func press(digit: Int) {
        switch focusedField {
        case .amount:
            input.appendAmountDigit(digit)
        case .time:
            input.timeEntry.append(digit)
        case nil:
            break
        }
    }

    func pressDelete() {
        switch focusedField {
        case .amount:
            input.deleteLastAmountDigit()
        case .time:
            input.timeEntry.deleteLast()
        case nil:
            break
        }
    }

    func select(unit: LoggedClimbInput.Unit) {
        input.select(unit: unit)
        focusedField = .amount
    }

    func setDate(_ date: Date) {
        input.date = date
        changedDate = true
    }

    /// Fills the steps and the time from the last climb. Steps, always: a last climb is a step
    /// count, and a floors field reading it back would round it.
    func applyLastClimb() {
        guard let lastClimb else { return }
        input.select(unit: .steps)
        input.amountDigits = String(min(lastClimb.steps, ClimbPacePolicy.maximumSteps))
        var time = ConsoleTimeEntry()
        for digit in Self.consoleDigits(for: lastClimb.duration) {
            time.append(digit)
        }
        input.timeEntry = time
        usedSameAsLast = true
    }

    /// The digits a console would have typed for a duration: `2400` seconds is `4000`.
    nonisolated static func consoleDigits(for duration: TimeInterval) -> [Int] {
        let total = max(Int(duration.rounded()), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        let text = hours > 0
            ? String(format: "%d%02d%02d", hours, minutes, seconds)
            : String(format: "%d%02d", minutes, seconds)
        return text.compactMap { $0.wholeNumberValue }
    }

    // MARK: - Photos

    var canAddMorePhotos: Bool {
        selectedPhotos.count < SelectedMediaPreparationService.maximumMediaCount
    }

    var remainingPhotoSlots: Int {
        max(SelectedMediaPreparationService.maximumMediaCount - selectedPhotos.count, 1)
    }

    /// What the media limits are judged against while a pick is being prepared.
    var photoLimitContext: (mediaCount: Int, videoCount: Int) {
        (selectedPhotos.count, selectedPhotos.filter(\.isVideo).count)
    }

    /// The picker owns `PhotosPickerItem`, a SwiftUI type, so the screen prepares the pick and
    /// hands the result here; this only keeps the loading flag and the list true.
    func mediaPreparationDidStart() {
        isLoadingMedia = true
    }

    func mediaPreparationDidFinish(adding items: [SelectedPhotoItem]) {
        selectedPhotos.append(contentsOf: items)
        isLoadingMedia = false
    }

    func removePhoto(id: UUID) {
        guard let index = selectedPhotos.firstIndex(where: { $0.id == id }) else { return }
        SelectedMediaPreparationService.cleanupTemporaryVideoFile(at: selectedPhotos[index].videoURL)
        selectedPhotos.remove(at: index)
        if highlightedPhotoId == id {
            highlightedPhotoId = nil
        }
    }

    /// The photo that leads the climb. With one photo there is nothing to choose.
    func highlightPhoto(id: UUID) {
        guard selectedPhotos.count > 1 else { return }
        highlightedPhotoId = highlightedPhotoId == id ? nil : id
    }

    // MARK: - Saving

    func save(modelContext: ModelContext, now: Date = Date()) async {
        guard canSave(now: now) else { return }

        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        var uploadedPhotos: [Photo] = []
        do {
            if !selectedPhotos.isEmpty {
                uploadedPhotos = try await photoService.uploadSelectedPhotos(selectedPhotos)
            }

            guard let workout = LoggedClimbService.makeWorkout(
                input: input,
                details: details,
                photos: uploadedPhotos,
                now: now
            ) else {
                saveErrorMessage = "Check the steps and time, then save again."
                return
            }
            if let highlighted = highlightedUploadedPhotoId(in: uploadedPhotos) {
                workout.highlightedPhotoId = highlighted
            }

            try LoggedClimbService.save(workout, modelContext: modelContext)
            savedWorkout = workout
            track(workout)
        } catch {
            if !uploadedPhotos.isEmpty {
                let orphaned = uploadedPhotos
                Task { try? await photoService.deletePhotos(orphaned) }
            }
            saveErrorMessage = (error as? LoggedClimbService.LoggingPaused)?.message
                ?? error.userFriendlyMessage
        }
    }

    /// Uploaded photos get new identifiers, so the picker's highlight maps across by position.
    private func highlightedUploadedPhotoId(in uploaded: [Photo]) -> UUID? {
        guard let highlightedPhotoId,
              let index = selectedPhotos.firstIndex(where: { $0.id == highlightedPhotoId }),
              uploaded.indices.contains(index) else { return nil }
        return uploaded[index].id
    }

    private func track(_ workout: Workout) {
        TelemetryManager.shared.track(
            WorkoutSessionAnalyticsEvent.workoutLogged(
                enteredAs: input.unit.rawValue,
                durationSeconds: Int(workout.duration.rounded()),
                steps: workout.steps,
                countsOnLeaderboards: workout.leaderboardStatus == .eligible,
                optionalFieldCount: optionalFieldCount,
                usedSameAsLast: usedSameAsLast,
                changedDate: changedDate
            )
        )
    }
}
