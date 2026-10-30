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
        case photo

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        chipRow
                        amountCard
                        timeCard
                        verdictMessage
                        optionalSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: 12) {
                    LogClimbKeypad(
                        onDigit: { viewModel.press(digit: $0) },
                        onDelete: { viewModel.pressDelete() }
                    )
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
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
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

    private var chipRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                dateChip
                sameAsLastChip
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 10) {
                dateChip
                sameAsLastChip
            }
        }
    }

    private var dateChip: some View {
        Button {
            activeSheet = .date
        } label: {
            Text(viewModel.dateChipTitle())
                .font(.montserratBold(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.1)))
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
                    .minimumScaleFactor(0.8)
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
                    .font(.montserratBold(size: 46))
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
                            .font(.montserratBold(size: 34))
                            .foregroundStyle(viewModel.isTimeEmpty ? .white.opacity(0.28) : .white)
                            .monospacedDigit()

                        if isFocused {
                            Rectangle()
                                .fill(Color.accent)
                                .frame(width: 3, height: 30)
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
            if case .aboveCeiling(let pace) = verdict {
                Text(LoggedClimbCopy.offTheBoardsNote(stepsPerMinute: pace))
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(Color.ascendCaution)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("log-climb-off-the-boards")
            }
        }
    }

    // MARK: - Optional

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OPTIONAL")
                .font(.montserratBold(size: 12))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 8) {
                optionalChip(
                    title: "Effort",
                    value: viewModel.details.effortRating.map { "\(Int($0))/5" },
                    sheet: .effort
                )
                optionalChip(
                    title: "Heart rate",
                    value: viewModel.details.averageHeartRate.map { "\($0)" },
                    sheet: .heartRate
                )
                optionalChip(
                    title: "Note",
                    value: viewModel.details.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "Added",
                    sheet: .note
                )
                optionalChip(
                    title: "Photo",
                    value: viewModel.selectedPhotos.isEmpty ? nil : "\(viewModel.selectedPhotos.count)",
                    sheet: .photo
                )
            }
        }
    }

    private func optionalChip(title: String, value: String?, sheet: OptionalSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            HStack(spacing: 4) {
                if value == nil {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accent)
                }
                Text(value.map { "\(title) \($0)" } ?? title)
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(value == nil ? Color.clear : Color.accent.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                value == nil ? Color.white.opacity(0.14) : Color.accent.opacity(0.6),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? "Add \(title)")
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
                        ProgressView().tint(.black)
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
        case .photo:
            LogClimbPhotoSheet(
                selectedPhotos: $viewModel.selectedPhotos,
                highlightedPhotoId: $viewModel.highlightedPhotoId
            )
            .appSheetStyle(.fitted())
        }
    }
}

/// The words the Log a climb flow says about the pace check, in one place so the form and the
/// result screen cannot drift apart.
enum LoggedClimbCopy {
    /// The note under a climb that has not been saved yet and will stay off the leaderboards.
    static func offTheBoardsNote(stepsPerMinute: Double) -> String {
        "\(paceOverLimit(stepsPerMinute)). This climb saves and stays off the leaderboards. Fix the steps or time and it ranks."
    }

    /// The note on a climb that is saved and off the leaderboards.
    static func savedOffTheBoardsNote(stepsPerMinute: Double) -> String {
        "\(paceOverLimit(stepsPerMinute)), so this climb stays off the leaderboards. Edit the steps or time and it ranks."
    }

    private static func paceOverLimit(_ stepsPerMinute: Double) -> String {
        let pace = Int(stepsPerMinute.rounded()).formatted()
        let ceiling = Int(ClimbPacePolicy.leaderboardCeilingStepsPerMinute).formatted()
        return "\(pace) steps a minute is over the \(ceiling) limit"
    }
}
