import PhotosUI
import SwiftData
import SwiftUI

/// LOG A CLIMB: type in a climb done without a live Ascend session.
///
/// Two numbers make a climb - steps (or floors) and the time off the console - and everything
/// else is one tap away. Save goes straight to the climb's result, not back to where the climber
/// came from, because the first thing they want to know is where it put them.
struct LogClimbView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: LogClimbViewModel
    @State private var activeSheet: OptionalSheet?
    @State private var savedWorkout: Workout?
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var mediaAlertMessage: String?

    init(lastClimb: LastClimbPreset?) {
        self.init(viewModel: LogClimbViewModel(lastClimb: lastClimb))
    }

    /// A screen over a view model a caller already holds, so a hosted test can put it in any
    /// state a climber could type it into.
    init(viewModel: LogClimbViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private enum OptionalSheet: String, Identifiable {
        case date
        case effort
        case heartRate
        case note

        var id: String { rawValue }

        init(_ field: LogClimbOptionalField) {
            switch field {
            case .effort: self = .effort
            case .heartRate: self = .heartRate
            case .note: self = .note
            case .photo: preconditionFailure("Photos are picked in place, never in a sheet")
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        chipRow
                        amountCard
                        timeCard
                        verdictMessage
                        LogClimbOptionalSection(
                            viewModel: viewModel,
                            onAddPhoto: { isPhotoPickerPresented = true },
                            onOpen: { activeSheet = OptionalSheet($0) }
                        )
                    }
                    .disabled(viewModel.isSaving)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                // With the keypad up and a pace note showing, the second row of OPTIONAL buttons
                // can sit past the fold; a fade says it scrolls instead of showing a button cut
                // off at the keypad.
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 16)
                    }
                }

                VStack(spacing: 12) {
                    if viewModel.focusedField != nil {
                        LogClimbKeypad(
                            onDigit: { viewModel.press(digit: $0) },
                            onDelete: { viewModel.pressDelete() }
                        )
                        .disabled(viewModel.isSaving)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    saveButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $savedWorkout) { workout in
                LoggedClimbResultView(workout: workout) {
                    dismiss()
                }
                .navigationBarBackButtonHidden(true)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $activeSheet, onDismiss: { viewModel.optionalInputFinished() }) { sheet in
            sheetContent(for: sheet)
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $pickedItems,
            maxSelectionCount: viewModel.remainingPhotoSlots,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPicked(items) }
        }
        .alert(
            "Media Limit Reached",
            isPresented: Binding(
                get: { mediaAlertMessage != nil },
                set: { if !$0 { mediaAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mediaAlertMessage ?? "")
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.focusedField)
        .trackOnce(screen: .logClimb)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("LOG A CLIMB")
                .font(.montserratBold(size: 16))
                .tracking(1.6)
                .foregroundStyle(.white)

            HStack {
                Button {
                    viewModel.close()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .accessibilityLabel("Close")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Chips

    /// One row, never stacked: a second row of chips pushes the OPTIONAL buttons under the keypad
    /// once the pace warning shows, so the Same as chip shrinks to fit beside the date instead.
    private var chipRow: some View {
        HStack(spacing: 10) {
            dateChip
            sameAsLastChip
            Spacer(minLength: 0)
        }
    }

    private var dateChip: some View {
        Button {
            activeSheet = .date
        } label: {
            Text(viewModel.dateChipTitle())
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("When: \(viewModel.dateChipTitle())")
        .accessibilityHint("Opens the date and time picker")
    }

    @ViewBuilder
    private var sameAsLastChip: some View {
        if let lastClimb = viewModel.lastClimb {
            Button {
                HapticsManager.shared.trigger(.selection)
                viewModel.applyLastClimb()
            } label: {
                Text(lastClimb.chipTitle())
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .strokeBorder(
                                Color.white.opacity(0.28),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lastClimb.chipTitle())
            .accessibilityHint("Fills in the steps and the time from your last climb")
        }
    }

    // MARK: - Fields

    private var amountCard: some View {
        let isFocused = viewModel.focusedField == .amount
        // Not a Button: the Steps / Floors toggle inside it is two buttons of its own, and a
        // button wrapped in a button swallows the inner tap.
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(viewModel.unit == .steps ? "STEPS" : "FLOORS")
                    .font(.montserratBold(size: 12))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityHidden(true)

                Spacer()

                unitToggle
            }

            HStack(spacing: 2) {
                Text(viewModel.amountDisplay.isEmpty ? "0" : viewModel.amountDisplay)
                    .font(.montserratBold(size: isFocused ? 46 : 30))
                    .foregroundStyle(viewModel.amountDisplay.isEmpty ? .white.opacity(0.28) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()

                if isFocused {
                    Rectangle()
                        .fill(Color.accent)
                        .frame(width: 3, height: 40)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.unit == .steps ? "Steps" : "Floors")
            .accessibilityValue(viewModel.amountDisplay.isEmpty ? "empty" : viewModel.amountDisplay)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fieldBackground(isFocused: isFocused))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            viewModel.focusedField = .amount
        }
    }

    private var unitToggle: some View {
        HStack(spacing: 6) {
            unitButton("Steps", unit: .steps)
            Text("·")
                .foregroundStyle(.white.opacity(0.35))
            unitButton("Floors", unit: .floors)
        }
        .font(.montserratBold(size: 13))
    }

    private func unitButton(_ title: String, unit: LoggedClimbInput.Unit) -> some View {
        Button {
            viewModel.select(unit: unit)
        } label: {
            Text(title)
                .foregroundStyle(viewModel.unit == unit ? .white : .white.opacity(0.4))
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(viewModel.unit == unit ? .isSelected : [])
    }

    private var timeCard: some View {
        let isFocused = viewModel.focusedField == .time
        return Button {
            viewModel.focusedField = .time
        } label: {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TIME")
                        .font(.montserratBold(size: 12))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.55))

                    HStack(spacing: 2) {
                        Text(viewModel.timeDisplay)
                            .font(.montserratBold(size: isFocused ? 36 : 30))
                            .foregroundStyle(viewModel.isTimeEmpty ? .white.opacity(0.28) : .white)
                            .monospacedDigit()

                        if isFocused {
                            Rectangle()
                                .fill(Color.accent)
                                .frame(width: 3, height: 32)
                                .accessibilityHidden(true)
                        }
                    }
                }

                Spacer()

                Text("From the console")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fieldBackground(isFocused: isFocused))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time from the console, \(viewModel.isTimeEmpty ? "empty" : viewModel.timeDisplay)")
    }

    private func fieldBackground(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accent : Color.white.opacity(0.1),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
    }

    // MARK: - Verdict

    /// The inline answer to what is typed: a refusal that blocks Save, or the note that a climb
    /// will save and stay off the boards. Caution orange, never lime - lime means earned.
    @ViewBuilder
    private var verdictMessage: some View {
        switch viewModel.validation() {
        case .incomplete:
            EmptyView()
        case .refused(let refusal):
            Text(refusal.message)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(Color.ascendCaution)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("log-climb-refusal")
        case .ready(let verdict):
            if case .aboveCeiling = verdict {
                Text(LoggedClimbCopy.offTheBoardsNote)
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(Color.ascendCaution)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("log-climb-off-the-boards")
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        let canSave = viewModel.canSave()
        return VStack(spacing: 8) {
            if let message = viewModel.saveErrorMessage {
                Text(message)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(Color.ascendCaution)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    await viewModel.save(modelContext: modelContext)
                    if let workout = viewModel.savedWorkout {
                        HapticsManager.shared.trigger(.success)
                        savedWorkout = workout
                    }
                }
            } label: {
                Group {
                    if viewModel.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("SAVE CLIMB")
                            .font(.montserratBold(size: 15))
                            .tracking(2)
                    }
                }
                .foregroundStyle(canSave ? .black : .white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(canSave ? Color.accent : Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityLabel("Save climb")
        }
    }

    // MARK: - Photos

    private func addPicked(_ items: [PhotosPickerItem]) async {
        viewModel.mediaPreparationDidStart()
        let limits = viewModel.photoLimitContext
        let outcome = await SelectedMediaPreparationService.prepareItems(
            items,
            currentMediaCount: limits.mediaCount,
            currentVideoCount: limits.videoCount
        )
        viewModel.mediaPreparationDidFinish(adding: outcome.wasCancelled ? [] : outcome.items)
        mediaAlertMessage = outcome.alertMessage
        pickedItems = []
        viewModel.optionalInputFinished()
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(for sheet: OptionalSheet) -> some View {
        switch sheet {
        case .date:
            DateTimePickerView(
                selectedDate: Binding(
                    get: { viewModel.date },
                    set: { viewModel.setDate($0) }
                )
            )
            .appSheetStyle(.dateTimePicker)
        case .effort:
            EffortRatingView(effortRating: $viewModel.details.effortRating)
                .appSheetStyle(.effortRating)
        case .heartRate:
            LogClimbHeartRateSheet(heartRate: $viewModel.details.averageHeartRate)
                .appSheetStyle(.fitted())
        case .note:
            LogClimbNoteSheet(note: $viewModel.details.note)
                .appSheetStyle(.fraction(0.6))
        }
    }
}

/// The words the Log a climb flow says about the pace check, in one place so the form and the
/// result screen cannot drift apart.
enum LoggedClimbCopy {
    /// The note under a climb that has not been saved yet and will stay off the leaderboards.
    /// Two lines at most, so the OPTIONAL buttons under it stay clear of the keypad.
    static var offTheBoardsNote: String {
        let ceiling = Int(ClimbPacePolicy.leaderboardCeilingStepsPerMinute).formatted()
        return "Over \(ceiling) steps a minute. This climb will not count on leaderboards."
    }

    /// The note on a climb that is saved and off the leaderboards.
    static func savedOffTheBoardsNote(stepsPerMinute: Double) -> String {
        "\(paceOverLimit(stepsPerMinute)), so this climb stays off the leaderboards. Edit the steps or time and it ranks."
    }

    /// The note on a saved climb dated before the climber joined, which is off the leaderboards
    /// whatever its pace: only climbs after the climber signed up count on leaderboards.
    static let savedBeforeJoiningNote = "This climb is from before you joined, so it stays off the leaderboards. It still counts for your history and personal bests."

    /// What a saved climb says about being off the leaderboards, or nil when nothing about it does.
    /// The join date is read first: a climb from before the account never ranks, so the pace note's
    /// "edit it and it ranks" would be false for it.
    static func savedNote(for workout: Workout, accountCreatedAt: Date? = AccountJoinDate.current()) -> String? {
        guard workout.origin != .live else { return nil }
        if ClimbPacePolicy.startedBeforeAccount(workout.date, accountCreatedAt: accountCreatedAt) {
            return savedBeforeJoiningNote
        }
        return workout.exceedsPaceCeiling ? savedOffTheBoardsNote(stepsPerMinute: workout.stepsPerMinute ?? 0) : nil
    }

    private static func paceOverLimit(_ stepsPerMinute: Double) -> String {
        let pace = Int(stepsPerMinute.rounded()).formatted()
        let ceiling = Int(ClimbPacePolicy.leaderboardCeilingStepsPerMinute).formatted()
        return "\(pace) steps a minute is over the \(ceiling) limit"
    }
}
