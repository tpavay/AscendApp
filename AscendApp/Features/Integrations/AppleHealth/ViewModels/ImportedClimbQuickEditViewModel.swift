import Foundation
import Observation
import SwiftData

/// State and rules for the quick edit sheet an automatic import opens.
///
/// The sheet exists for the half-minute after a watch finished: fix the steps to match the
/// console, add a note, a photo or an effort, and be done. It edits one climb and nothing else;
/// time, date and heart rate stay what Apple Health recorded, and the full editor is one tap away
/// from the climb's own screen.
@MainActor
@Observable
final class ImportedClimbQuickEditViewModel {
    let workout: Workout

    var stepsText: String
    var note: String
    var effortRating: Double?
    var selectedPhotos: [SelectedPhotoItem] = []
    var highlightedPhotoId: UUID?
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let originalSteps: Int
    @ObservationIgnored private let photoService: PhotoService
    @ObservationIgnored private let uploadMedia: @MainActor ([SelectedPhotoItem]) async throws -> [Photo]
    @ObservationIgnored private let applyUpdate: @MainActor (ModelContext, LeaderboardWorkoutSnapshot, Workout) throws -> Void

    init(
        workout: Workout,
        photoService: PhotoService = PhotoService(),
        uploadMedia: (@MainActor ([SelectedPhotoItem]) async throws -> [Photo])? = nil,
        applyUpdate: @escaping @MainActor (ModelContext, LeaderboardWorkoutSnapshot, Workout) throws -> Void = { context, before, workout in
            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: context,
                mutation: .updated(before: before, after: LeaderboardWorkoutSnapshot(workout: workout)),
                changedWorkouts: [workout]
            )
        }
    ) {
        self.workout = workout
        self.photoService = photoService
        self.uploadMedia = uploadMedia ?? { try await photoService.uploadSelectedPhotos($0) }
        self.applyUpdate = applyUpdate
        self.originalSteps = workout.steps
        self.stepsText = workout.recordedSteps.map(String.init) ?? ""
        self.note = workout.notes
        self.effortRating = workout.effortRating
    }

    // MARK: - What the sheet reads

    var dateLine: String {
        let time = workout.date.formatted(.dateTime.hour().minute())
        let day = Calendar.current.isDateInToday(workout.date)
            ? "Today"
            : workout.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day) · \(time) · from Apple Health"
    }

    var durationText: String { ImportsRowFormat.durationText(workout.duration) }

    var averageHeartRateText: String { workout.avgHeartRate.map(String.init) ?? "—" }

    /// The steps as typed, or nil while the field is empty or not a number.
    var enteredSteps: Int? {
        let digits = stepsText.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    var stepsChanged: Bool { (enteredSteps ?? 0) != originalSteps }

    /// What the pace check says about the steps as typed, so the sheet can say up front that a
    /// number will stay off the boards or cannot be saved.
    var stepsVerdict: ClimbPacePolicy.Verdict? {
        guard let steps = enteredSteps, steps > 0 else { return nil }
        if steps > ClimbPacePolicy.maximumSteps { return .absurd(stepsPerMinute: .infinity) }
        return ClimbPacePolicy.verdict(steps: steps, duration: workout.duration)
    }

    /// Why Done is refused, or nil when it can go.
    var refusalMessage: String? {
        guard let verdict = stepsVerdict, !verdict.isSaveable else { return nil }
        if let steps = enteredSteps, steps > ClimbPacePolicy.maximumSteps {
            return LoggedClimbValidation.Refusal.tooManySteps.message
        }
        if case .absurd(let pace) = verdict {
            return LoggedClimbValidation.Refusal.impossiblePace(stepsPerMinute: Int(pace.rounded())).message
        }
        return nil
    }

    var offTheBoardsNote: String? {
        if case .aboveCeiling = stepsVerdict { return LoggedClimbCopy.offTheBoardsNote }
        return nil
    }

    var canFinish: Bool { refusalMessage == nil && !isSaving }

    /// Whether the climb can take another photo. A full climb has nothing for the picker to offer.
    var hasRoomForPhotos: Bool {
        workout.photos.count < SelectedMediaPreparationService.maximumMediaCount
    }

    var photoButtonTitle: String {
        guard hasRoomForPhotos else {
            let limit = SelectedMediaPreparationService.maximumMediaCount
            return "\(workout.photos.count) of \(limit) photos"
        }
        return selectedPhotos.isEmpty ? "Photo" : "Photo · \(selectedPhotos.count)"
    }

    // MARK: - Actions

    /// Applies what was typed and saves. Returns whether the sheet can close.
    ///
    /// The pace check runs again only when the steps moved: a note, a photo or an effort rating
    /// changes nothing the pace depends on, so it can never put the climb on or take it off the
    /// boards.
    func finish(modelContext: ModelContext) async -> Bool {
        guard canFinish else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let before = LeaderboardWorkoutSnapshot(workout: workout)
        var uploaded: [Photo] = []
        do {
            let room = max(SelectedMediaPreparationService.maximumMediaCount - workout.photos.count, 0)
            let uploadable = Array(selectedPhotos.prefix(room))
            if !uploadable.isEmpty {
                uploaded = try await uploadMedia(uploadable)
            }

            if stepsChanged {
                workout.steps = enteredSteps ?? 0
                workout.recalculateFloorsFromSteps()
                workout.refreshLeaderboardStatus()
            }
            workout.notes = note.trimmingCharacters(in: .whitespacesAndNewlines)
            workout.effortRating = effortRating
            if !uploaded.isEmpty {
                workout.photos += uploaded
                if workout.highlightedPhotoId == nil {
                    workout.highlightedPhotoId = highlightedUploadedID(in: uploaded) ?? uploaded.first?.id
                }
            }

            try modelContext.save()
            try applyUpdate(modelContext, before, workout)
            return true
        } catch {
            if !uploaded.isEmpty {
                let orphaned = uploaded
                Task { try? await photoService.deletePhotos(orphaned) }
            }
            errorMessage = error.userFriendlyMessage
            return false
        }
    }

    private func highlightedUploadedID(in uploaded: [Photo]) -> UUID? {
        guard let highlightedPhotoId,
              let index = selectedPhotos.firstIndex(where: { $0.id == highlightedPhotoId }),
              uploaded.indices.contains(index) else { return nil }
        return uploaded[index].id
    }
}
