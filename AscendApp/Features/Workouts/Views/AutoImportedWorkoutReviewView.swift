import PhotosUI
import SwiftData
import SwiftUI

struct AutoImportedWorkoutReviewView: View {
    private enum ReviewField: Hashable {
        case workoutName
        case notes
        case steps
    }

    let workout: Workout
    let onDone: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var importCoordinator = WorkoutImportCoordinator.shared

    @State private var workoutName = ""
    @State private var notes = ""
    @State private var durationHours = ""
    @State private var durationMinutes = ""
    @State private var durationSeconds = ""
    @State private var durationFormatted = ""
    @State private var stepsValue = ""

    @State private var existingPhotos: [Photo] = []
    @State private var selectedImages: [SelectedPhotoItem] = []
    @State private var photosMarkedForDeletion: [Photo] = []
    @State private var photoPendingDeletion: Photo?

    @State private var showingDurationPicker = false
    @State private var durationPickerHours = 0
    @State private var durationPickerMinutes = 0
    @State private var durationPickerSeconds = 0

    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false
    @State private var errorTitle = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: ReviewField?

    private let photoService = PhotoService()

    private var isFormValid: Bool {
        let trimmedName = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = Int(durationMinutes)
        let seconds = Int(durationSeconds)
        let hours = Int(durationHours) ?? 0
        let totalDurationSeconds = hours * 3600 + (minutes ?? 0) * 60 + (seconds ?? 0)
        let stepsValid = stepsValue.isEmpty || Int(stepsValue) != nil
        let workoutTotalsValid = WorkoutInputValidation.isValidWorkoutTotals(
            stepsValue: stepsValue,
            durationHours: hours,
            durationMinutes: minutes ?? 0,
            durationSeconds: seconds ?? 0
        )

        return !isSaving &&
            !isDeleting &&
            trimmedName.count <= 50 &&
            minutes != nil &&
            seconds != nil &&
            (minutes ?? 0) < 60 &&
            (seconds ?? 0) < 60 &&
            totalDurationSeconds > 0 &&
            stepsValid &&
            workoutTotalsValid
    }

    private var totalDuration: TimeInterval {
        let hours = Int(durationHours) ?? 0
        let minutes = Int(durationMinutes) ?? 0
        let seconds = Int(durationSeconds) ?? 0
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    private var effectiveName: String {
        let trimmedName = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? Workout.generateDefaultName(for: workout.date) : trimmedName
    }

    private var effectiveColorScheme: ColorScheme {
        colorScheme
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    FormTextField(
                        label: "Workout Name",
                        isRequired: false,
                        text: $workoutName,
                        focusedField: $focusedField,
                        fieldIdentifier: ReviewField.workoutName,
                        maxLength: 50
                    )

                    FormTextEditor(
                        label: "Description",
                        isRequired: false,
                        placeholder: "Add a description for your workout",
                        text: $notes,
                        focusedField: $focusedField,
                        fieldIdentifier: ReviewField.notes
                    )

                    mediaSection

                    FormSection(title: "Workout Details") {
                        VStack(spacing: 12) {
                            importedDateRow

                            FormButton(
                                label: "Duration",
                                isRequired: true,
                                icon: "clock",
                                value: durationFormatted,
                                action: {
                                    syncDurationPicker()
                                    showingDurationPicker = true
                                }
                            )

                            FormTextField(
                                label: "Steps",
                                isRequired: false,
                                icon: "figure.stairs",
                                keyboardType: .numberPad,
                                text: $stepsValue,
                                focusedField: $focusedField,
                                fieldIdentifier: ReviewField.steps
                            )
                            .onChange(of: stepsValue) { _, newValue in
                                stepsValue = filterNumericInput(newValue)
                            }
                        }
                    }

                    deleteSection
                }
                .padding(20)
                .background(sheetContentSurface)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .themedBackground()
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await completeReview()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .accent))
                        } else {
                            Text("Done")
                        }
                    }
                    .font(.montserratSemiBold)
                    .foregroundStyle(isFormValid ? .accent : .gray)
                    .disabled(!isFormValid || isDeleting)
                }
            }
            .keyboardDoneToolbar {
                focusedField = nil
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showingDurationPicker) {
            DurationPickerSheet(
                hours: $durationPickerHours,
                minutes: $durationPickerMinutes,
                seconds: $durationPickerSeconds
            ) {
                setDuration(
                    hours: durationPickerHours,
                    minutes: durationPickerMinutes,
                    seconds: durationPickerSeconds
                )
                showingDurationPicker = false
            }
            .appSheetStyle(.durationPicker, isInteractiveDismissDisabled: true)
        }
        .sheet(item: $photoPendingDeletion) { _ in
            DeletePhotoConfirmationView(
                onDelete: {
                    if let photoPendingDeletion {
                        removeExistingPhoto(photoPendingDeletion)
                    }
                },
                onCancel: {
                    photoPendingDeletion = nil
                }
            )
        }
        .sheet(isPresented: $showingDeleteConfirmation) {
            ConfirmationView(
                title: "Remove Import",
                message: "Remove \"\(effectiveName)\" from Ascend? This Apple Health workout will not auto-import again.",
                confirmButtonText: "Remove",
                isDestructive: true,
                isLoading: isDeleting,
                onCancel: {
                    showingDeleteConfirmation = false
                },
                onConfirm: {
                    Task {
                        await deleteWorkout()
                    }
                }
            )
            .appSheetStyle(.destructiveConfirmation)
        }
        .alert(errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            populateFields()
        }
        .onDisappear {
            cleanupVideoFiles()
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        FormSection(title: "Media") {
            if existingPhotos.isEmpty {
                PhotoGalleryView(
                    selectedImages: $selectedImages,
                    existingMediaCount: 0,
                    existingVideoCount: 0
                )
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(existingPhotos) { photo in
                            ZStack(alignment: .topTrailing) {
                                LoadablePhotoView(
                                    photo: photo,
                                    size: CGSize(width: 110, height: 110),
                                    cornerRadius: 12
                                )

                                MediaTileDeleteButton {
                                    photoPendingDeletion = photo
                                }
                                .padding(6)
                            }
                        }

                        PhotoGalleryView(
                            selectedImages: $selectedImages,
                            existingMediaCount: existingPhotos.count,
                            existingVideoCount: existingPhotos.filter(\.isVideo).count,
                            embeddedInScrollRow: true
                        )
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var deleteSection: some View {
        FormSection(title: "Actions") {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Text("Remove Import")
            }
            .appSheetButtonStyle(tone: .destructive)
            .disabled(isSaving || isDeleting)
        }
    }

    private var importedDateRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.gray)
                .frame(width: 24)

            Text(formatWorkoutDateTime())
                .font(.montserratRegular(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
    }

    private var sheetContentSurface: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(effectiveColorScheme == .dark ? .white.opacity(0.03) : .black.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(
                        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08),
                        lineWidth: 1
                    )
            )
    }

    private func populateFields() {
        workoutName = workout.name
        notes = workout.notes
        stepsValue = workout.steps == 0 ? "" : String(workout.steps)
        existingPhotos = workout.photos
        photosMarkedForDeletion = []
        selectedImages = []

        let totalSeconds = Int(workout.duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        durationHours = String(format: "%02d", hours)
        durationMinutes = String(format: "%02d", minutes)
        durationSeconds = String(format: "%02d", seconds)
        durationFormatted = workout.durationFormatted
    }

    private func formatWorkoutDateTime() -> String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        if calendar.isDateInToday(workout.date) {
            return "Today at \(timeFormatter.string(from: workout.date))"
        } else if calendar.isDateInYesterday(workout.date) {
            return "Yesterday at \(timeFormatter.string(from: workout.date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return "\(dateFormatter.string(from: workout.date)) at \(timeFormatter.string(from: workout.date))"
        }
    }

    private func syncDurationPicker() {
        durationPickerHours = Int(durationHours) ?? 0
        durationPickerMinutes = Int(durationMinutes) ?? 0
        durationPickerSeconds = Int(durationSeconds) ?? 0
    }

    private func setDuration(hours: Int, minutes: Int, seconds: Int) {
        let clampedHours = min(max(hours, 0), 999)
        let clampedMinutes = min(max(minutes, 0), 59)
        let clampedSeconds = min(max(seconds, 0), 59)

        durationHours = String(format: "%02d", clampedHours)
        durationMinutes = String(format: "%02d", clampedMinutes)
        durationSeconds = String(format: "%02d", clampedSeconds)

        if clampedHours > 0 {
            durationFormatted = "\(clampedHours):\(String(format: "%02d", clampedMinutes)):\(String(format: "%02d", clampedSeconds))"
        } else {
            durationFormatted = "\(String(format: "%02d", clampedMinutes)):\(String(format: "%02d", clampedSeconds))"
        }
    }

    private func filterNumericInput(_ input: String) -> String {
        input.filter(\.isNumber)
    }

    private func removeExistingPhoto(_ photo: Photo) {
        if !photosMarkedForDeletion.contains(where: { $0.id == photo.id }) {
            photosMarkedForDeletion.append(photo)
        }

        existingPhotos.removeAll { $0.id == photo.id }
        photoPendingDeletion = nil
    }

    private func cleanupVideoFiles() {
        for item in selectedImages {
            if let videoURL = item.videoURL {
                try? FileManager.default.removeItem(at: videoURL)
            }
        }
    }

    @MainActor
    private func completeReview() async {
        focusedField = nil
        await Task.yield()
        await saveWorkout()
    }

    @MainActor
    private func saveWorkout() async {
        guard isFormValid, !isSaving else { return }

        isSaving = true
        errorMessage = nil

        let selectedImagesSnapshot = selectedImages
        let existingPhotosSnapshot = existingPhotos
        let deletedPhotosSnapshot = photosMarkedForDeletion
        let leaderboardSnapshotBeforeEdit = LeaderboardWorkoutSnapshot(workout: workout)
        var newlyUploadedPhotos: [Photo] = []

        do {
            if !selectedImagesSnapshot.isEmpty {
                newlyUploadedPhotos = try await photoService.uploadSelectedPhotos(selectedImagesSnapshot)
            }

            let steps = Int(stepsValue) ?? 0
            guard WorkoutPlausibilityPolicy.hasPlausibleTotals(
                steps: steps,
                duration: totalDuration
            ) else {
                throw WorkoutServiceError.invalidWorkoutData
            }

            workout.name = effectiveName
            workout.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            workout.duration = totalDuration
            workout.steps = steps
            workout.floors = Workout.stepsToFloors(steps)
            workout.stepsPerFloor = Workout.defaultStepsPerFloor

            let combinedPhotos = existingPhotosSnapshot + newlyUploadedPhotos
            workout.photos = combinedPhotos
            if let highlightedPhotoID = workout.highlightedPhotoId,
               !combinedPhotos.contains(where: { $0.id == highlightedPhotoID }) {
                workout.highlightedPhotoId = combinedPhotos.first?.id
            } else if workout.highlightedPhotoId == nil {
                workout.highlightedPhotoId = combinedPhotos.first?.id
            }

            try modelContext.save()

            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: modelContext,
                mutation: .updated(
                    before: leaderboardSnapshotBeforeEdit,
                    after: LeaderboardWorkoutSnapshot(workout: workout)
                )
            )

            if !deletedPhotosSnapshot.isEmpty {
                Task {
                    try? await photoService.deletePhotos(deletedPhotosSnapshot)
                }
            }

            cleanupVideoFiles()
            onDone()
        } catch {
            if !newlyUploadedPhotos.isEmpty {
                Task {
                    try? await photoService.deletePhotos(newlyUploadedPhotos)
                }
            }

            cleanupVideoFiles()
            errorTitle = "Unable to Save"
            errorMessage = error.userFriendlyMessage
        }

        isSaving = false
    }

    @MainActor
    private func deleteWorkout() async {
        guard !isDeleting else { return }

        isDeleting = true

        await MediaUploadManager.shared.cancelUploads(for: workout.id, modelContext: modelContext)

        if !workout.photos.isEmpty {
            do {
                try await photoService.deletePhotos(workout.photos)
            } catch let error as PhotoDeletionError {
                switch error {
                case .partialFailure(let result):
                    errorTitle = "Unable to Delete"
                    errorMessage = "Failed to delete \(result.failedCount) photo(s) from cloud storage. Please check your internet connection and try again."
                case .timeout:
                    errorTitle = "Unable to Delete"
                    errorMessage = "Photo deletion timed out. Please check your internet connection and try again."
                case .allRetriesExhausted:
                    errorTitle = "Unable to Delete"
                    errorMessage = "Failed to delete photos after multiple attempts. Please try again later."
                }

                showingDeleteConfirmation = false
                isDeleting = false
                return
            } catch {
                errorTitle = "Unable to Delete"
                errorMessage = "Failed to delete photos from cloud storage. Please check your internet connection and try again."
                showingDeleteConfirmation = false
                isDeleting = false
                return
            }
        }

        let deletedSnapshot = LeaderboardWorkoutSnapshot(workout: workout)
        modelContext.delete(workout)

        do {
            try modelContext.save()

            if let appleHealthExternalRecordID = appleHealthExternalRecordID {
                importCoordinator.ignoreAppleHealthWorkout(externalRecordID: appleHealthExternalRecordID)
            }

            try WorkoutMutationHandler.shared.workoutsDidChange(
                modelContext: modelContext,
                mutation: .deleted([deletedSnapshot])
            )

            cleanupVideoFiles()
            showingDeleteConfirmation = false
            isDeleting = false
            onDelete()
        } catch {
            errorTitle = "Unable to Delete"
            errorMessage = "Failed to delete workout from local storage. Please try again."
            showingDeleteConfirmation = false
            isDeleting = false
        }
    }

    private var appleHealthExternalRecordID: String? {
        workout.sourceLink(for: .appleHealth)?.externalRecordID ?? workout.healthKitUUID
    }
}
