import SwiftData
import SwiftUI

/// CLIMB IMPORTED: the half-minute after a watch finished. Fix the steps to match the console, add
/// a note, a photo or an effort, tap Done - or remove the climb.
///
/// Reached from the "Climb imported" notification and the green strip on Home, and nowhere else:
/// every other way of opening an imported climb is its full summary.
struct ImportedClimbQuickEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ImportedClimbQuickEditViewModel
    @State private var activeSheet: OptionalSheet?
    @FocusState private var focusedField: Field?
    /// Mounts the steps field. Focus cannot do it: `@FocusState` drops a value no mounted view is
    /// bound to, so the field gets focus once it is on screen.
    @State private var isEditingSteps = false
    @State private var isRemoving = false

    private let importService: AppleHealthImportService

    init(
        workout: Workout,
        importService: AppleHealthImportService = .shared
    ) {
        self.init(viewModel: ImportedClimbQuickEditViewModel(workout: workout), importService: importService)
    }

    init(viewModel: ImportedClimbQuickEditViewModel, importService: AppleHealthImportService) {
        _viewModel = State(initialValue: viewModel)
        self.importService = importService
    }

    private enum Field: Hashable {
        case steps
        case note
    }

    private enum OptionalSheet: String, Identifiable {
        case photo
        case effort

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 10) {
                statTile(title: "TIME", value: viewModel.durationText)
                stepsTile
                statTile(title: "AVG BPM", value: viewModel.averageHeartRateText)
            }

            if let refusal = viewModel.refusalMessage {
                caption(refusal, tone: .caution)
                    .accessibilityIdentifier("quick-edit-refusal")
            } else if let note = viewModel.offTheBoardsNote {
                caption(note, tone: .caution)
                    .accessibilityIdentifier("quick-edit-off-the-boards")
            } else {
                caption("Exactly what Apple Health recorded. Tap to change it.", tone: .quiet)
            }

            noteField

            HStack(spacing: 12) {
                optionButton(
                    title: viewModel.photoButtonTitle,
                    systemImage: "camera"
                ) { activeSheet = .photo }
                .disabled(!viewModel.hasRoomForPhotos)
                .opacity(viewModel.hasRoomForPhotos ? 1 : 0.5)

                optionButton(
                    title: viewModel.effortRating.map { "Effort · \(Int($0))" } ?? "Effort",
                    systemImage: nil
                ) { activeSheet = .effort }
            }

            if let message = viewModel.errorMessage {
                caption(message, tone: .caution)
            }

            doneButton

            Button {
                isRemoving = true
                Task {
                    await importService.removeImportedClimb(workoutID: viewModel.workout.id)
                    dismiss()
                }
            } label: {
                Text("Remove this climb")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
        }
        .disabled(viewModel.isSaving || isRemoving)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .photo:
                LogClimbPhotoSheet(
                    selectedPhotos: $viewModel.selectedPhotos,
                    highlightedPhotoId: $viewModel.highlightedPhotoId,
                    existingMediaCount: viewModel.workout.photos.count,
                    existingVideoCount: viewModel.workout.photos.filter(\.isVideo).count
                )
                .appSheetStyle(.fitted())
            case .effort:
                EffortRatingView(effortRating: $viewModel.effortRating)
                    .appSheetStyle(.effortRating)
            }
        }
        .trackOnce(screen: .importedClimbQuickEdit)
        .appSheetStyle(.fitted(), isInteractiveDismissDisabled: viewModel.isSaving || isRemoving)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 14) {
            Image("appleHealth-icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Climb imported")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(.white)
                Text(viewModel.dateLine)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.montserratBold(size: 12))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tileBackground(isHighlighted: false))
        .accessibilityElement(children: .combine)
    }

    /// The one tile that edits: highlighted, with a pencil, because matching the console is the
    /// reason this sheet exists.
    private var stepsTile: some View {
        Button {
            isEditingSteps = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if isEditingSteps {
                        TextField("—", text: $viewModel.stepsText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .steps)
                            .font(.montserratBold(size: 24))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                            .onAppear { focusedField = .steps }
                            .onChange(of: viewModel.stepsText) { _, newValue in
                                let digits = WorkoutInputValidation.filterNumericInput(newValue)
                                viewModel.stepsText = String(digits.prefix(6))
                            }
                            .onChange(of: focusedField) { _, field in
                                if field != .steps { isEditingSteps = false }
                            }
                    } else {
                        // Grouped when at rest, like every other number on the screen; the plain
                        // digits only while they are being typed.
                        Text(viewModel.enteredSteps.map { $0.formatted() } ?? "—")
                            .font(.montserratBold(size: 24))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)
                }
                Text("STEPS")
                    .font(.montserratBold(size: 12))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tileBackground(isHighlighted: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Steps")
        .accessibilityValue(viewModel.enteredSteps.map { $0.formatted() } ?? "Not recorded")
        .accessibilityHint("Edits the step count")
    }

    private func tileBackground(isHighlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Color.accent : .white.opacity(0.1),
                        lineWidth: isHighlighted ? 1.5 : 1
                    )
            )
    }

    private enum CaptionTone { case quiet, caution }

    private func caption(_ text: String, tone: CaptionTone) -> some View {
        Text(text)
            .font(.montserratMedium(size: 14))
            .foregroundStyle(tone == .caution ? Color.ascendCaution : .white.opacity(0.58))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var noteField: some View {
        TextField("Add a note...", text: $viewModel.note, axis: .vertical)
            .focused($focusedField, equals: .note)
            .lineLimit(1...3)
            .font(.montserratMedium(size: 17))
            .foregroundStyle(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .onChange(of: viewModel.note) { _, newValue in
                if newValue.count > WorkoutInputValidation.notesMaxLength {
                    viewModel.note = String(newValue.prefix(WorkoutInputValidation.notesMaxLength))
                }
            }
    }

    private func optionButton(title: String, systemImage: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.montserratBold(size: 16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var doneButton: some View {
        Button {
            Task {
                focusedField = nil
                if await viewModel.finish(modelContext: modelContext) {
                    importService.retireHomeNotice()
                    HapticsManager.shared.trigger(.success)
                    dismiss()
                }
            }
        } label: {
            Group {
                if viewModel.isSaving {
                    ProgressView().tint(.black)
                } else {
                    Text("DONE")
                        .font(.montserratBold(size: 17))
                        .tracking(2)
                }
            }
            .foregroundStyle(viewModel.canFinish ? .black : .white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(viewModel.canFinish ? Color.accent : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canFinish)
    }
}
