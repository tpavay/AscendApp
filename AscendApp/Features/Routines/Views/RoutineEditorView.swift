import SwiftUI
import SwiftData

private enum RoutineEditorField: Hashable {
    case name
    case description
}

/// Building a routine is dragging blocks on a timeline. There is no interval list and no
/// interval creator: the timeline carries the level and the duration inside each block, and
/// the only control under it is the step type.
struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settingsManager = SettingsManager.shared
    @State private var viewModel = RoutineEditorViewModel()
    @State private var showSaveError = false
    @State private var interactionBaseline: RoutineEditorStats?
    @State private var coachMark: RoutineBuilderCoachMark?
    @AppStorage(RoutineBuilderCoachMark.seenStorageKey) private var hasSeenCoachMarks = false
    @FocusState private var focusedField: RoutineEditorField?

    let routine: Routine?
    let folderId: UUID?
    /// The sheet must not treat a vertical drag on a block as a dismissal. Cancel in the top
    /// left is still how you leave.
    @Binding var isInteractingWithTimeline: Bool
    var onSave: ((Routine) -> Void)?

    init(
        routine: Routine? = nil,
        folderId: UUID? = nil,
        isInteractingWithTimeline: Binding<Bool> = .constant(false),
        onSave: ((Routine) -> Void)? = nil
    ) {
        self.routine = routine
        self.folderId = folderId
        self._isInteractingWithTimeline = isInteractingWithTimeline
        self.onSave = onSave
    }

    private var liveStatKeys: Set<RoutineEditorStats.Key> {
        guard let interactionBaseline else { return [] }
        return viewModel.stats.changedKeys(comparedTo: interactionBaseline)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoutineEditorNavigationBar(
                    title: viewModel.navigationTitle,
                    canSave: viewModel.canSave,
                    onCancel: { dismiss() },
                    onSave: saveRoutine
                )

                RoutineEditorNameField(
                    text: $viewModel.name,
                    focusedField: $focusedField
                )

                RoutineEditorStatsRow(stats: viewModel.stats, liveKeys: liveStatKeys)

                timeline
                    .routineCoachMarkTarget(.timeline)

                if let selectedInterval = viewModel.selectedInterval {
                    RoutineStepTypeControl(
                        stepType: viewModel.selectedStepType,
                        onSelect: { viewModel.setStepType($0, forIntervalWithId: selectedInterval.id) },
                        onDelete: { deleteInterval(withId: selectedInterval.id) }
                    )
                    .routineCoachMarkTarget(.stepControl)
                }

                addIntervalButton
                    .routineCoachMarkTarget(.add)

                RoutineEditorAdvancedSettingsSection(
                    isExpanded: $viewModel.isAdvancedExpanded,
                    description: $viewModel.routineDescription,
                    defaultWeightConfiguration: $viewModel.defaultWeightConfiguration,
                    measurementSystem: settingsManager.measurementSystem,
                    focusedField: $focusedField
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keyboardDoneToolbar {
            focusedField = nil
        }
        .overlayPreferenceValue(RoutineBuilderCoachMarkAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let coachMark {
                    RoutineBuilderCoachMarkOverlay(
                        mark: coachMark,
                        targetRect: anchors[coachMark].map { proxy[$0] },
                        containerSize: proxy.size,
                        onNext: advanceCoachMarks,
                        onSkip: finishCoachMarks
                    )
                }
            }
        }
        .alert("Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Failed to save routine.")
        }
        .onAppear {
            viewModel.configure(modelContext: modelContext, routine: routine, folderId: folderId)
            startCoachMarksIfNeeded()
        }
        .onChange(of: viewModel.intervals.count) {
            startCoachMarksIfNeeded()
        }
        .onDisappear {
            isInteractingWithTimeline = false
        }
        .appSheetBackground()
    }

    // MARK: - Timeline

    private var timeline: some View {
        RoutineTimelineEditor(
            intervals: viewModel.intervals,
            selectedIntervalId: viewModel.selectedIntervalId,
            onSelect: { viewModel.select(intervalWithId: $0) },
            onSetLevel: { viewModel.setLevel($1, forIntervalWithId: $0) },
            onSetDuration: { viewModel.setDuration($1, forIntervalWithId: $0) },
            onAdjustLevel: { viewModel.adjustLevel(by: $1, forIntervalWithId: $0) },
            onAdjustDuration: { viewModel.adjustDuration(bySteps: $1, forIntervalWithId: $0) },
            onCycleStepType: { viewModel.cycleStepType(forIntervalWithId: $0) },
            onDelete: { deleteInterval(withId: $0) },
            onMove: { viewModel.moveInterval(fromIndex: $0, toIndex: $1) },
            onInteractingChange: handleTimelineInteraction
        )
    }

    private var addIntervalButton: some View {
        Button {
            withAnimation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion)) {
                viewModel.addInterval()
            }
            HapticsManager.shared.trigger(.lightImpact)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))

                Text("Add Interval")
                    .font(.montserratSemiBold(size: 16))
            }
            .foregroundStyle(Color.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        Color.accent.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add interval")
        .accessibilityHint("Adds a Standard interval at level 1.")
    }

    // MARK: - Actions

    private func handleTimelineInteraction(_ isInteracting: Bool) {
        isInteractingWithTimeline = isInteracting
        interactionBaseline = isInteracting ? viewModel.stats : nil
    }

    private func deleteInterval(withId id: UUID) {
        withAnimation(RoutineTimelineMotion.resize(reduceMotion: reduceMotion)) {
            viewModel.deleteInterval(withId: id)
        }
    }

    private func saveRoutine() {
        do {
            let savedRoutine = try viewModel.save()
            HapticsManager.shared.trigger(.success)
            onSave?(savedRoutine)
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
            showSaveError = true
        }
    }

    // MARK: - Coach marks

    /// The walkthrough waits until there is a timeline worth pointing at, so the first
    /// spotlight never lands on an empty plot.
    private func startCoachMarksIfNeeded() {
        guard !hasSeenCoachMarks, coachMark == nil, !viewModel.intervals.isEmpty else { return }
        withAnimation(RoutineTimelineMotion.coachMark(reduceMotion: reduceMotion)) {
            coachMark = .timeline
        }
    }

    private func advanceCoachMarks() {
        guard let next = coachMark?.next else {
            finishCoachMarks()
            return
        }

        withAnimation(RoutineTimelineMotion.coachMark(reduceMotion: reduceMotion)) {
            coachMark = next
        }
    }

    private func finishCoachMarks() {
        hasSeenCoachMarks = true
        withAnimation(RoutineTimelineMotion.coachMark(reduceMotion: reduceMotion)) {
            coachMark = nil
        }
    }
}

private struct RoutineEditorNavigationBar: View {
    let title: String
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .font(.montserratMedium(size: 15))
            .foregroundStyle(Color.customGray)
            .buttonStyle(.plain)
            .frame(minWidth: 64, alignment: .leading)

            Spacer()

            Text(title)
                .font(.montserratSemiBold(size: 17))
                .foregroundStyle(.white)

            Spacer()

            Button("Save") {
                onSave()
            }
            .font(.montserratSemiBold(size: 15))
            .foregroundStyle(.accent.opacity(canSave ? 1 : 0.3))
            .disabled(!canSave)
            .buttonStyle(.plain)
            .frame(minWidth: 64, alignment: .trailing)
        }
    }
}

/// The name is the document title, not a boxed field - which buys the timeline 40pt.
private struct RoutineEditorNameField: View {
    @Binding var text: String
    let focusedField: FocusState<RoutineEditorField?>.Binding

    var body: some View {
        TextField("", text: $text, prompt: Text("Name it").foregroundStyle(.white.opacity(0.22)))
            .font(.montserratSemiBold(size: 22))
            .foregroundStyle(.white)
            .tint(.accent)
            .focused(focusedField, equals: .name)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
            .accessibilityLabel("Routine name")
    }
}

private struct RoutineEditorSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.montserratSemiBold(size: 12))
            .tracking(0.8)
            .foregroundStyle(Color.customGray)
    }
}

private struct RoutineEditorAdvancedSettingsSection: View {
    @Binding var isExpanded: Bool
    @Binding var description: String
    @Binding var defaultWeightConfiguration: WeightConfiguration
    let measurementSystem: MeasurementSystem
    var focusedField: FocusState<RoutineEditorField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Advanced Settings")
                        .font(.montserratMedium(size: 16))
                        .foregroundStyle(Color.customGray)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.customGray)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        RoutineEditorSectionLabel(text: "Description")

                        TextField("Add a description", text: $description, axis: .vertical)
                            .font(.montserratRegular(size: 15))
                            .foregroundStyle(.white)
                            .lineLimit(3...6)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.jetLighter.opacity(0.5))
                            )
                            .focused(focusedField, equals: .description)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        RoutineEditorSectionLabel(text: "Default Weights")

                        WeightEntryView(
                            configuration: $defaultWeightConfiguration,
                            measurementSystem: measurementSystem
                        )
                    }
                }
            }
        }
    }
}

#Preview("New Routine") {
    RoutineEditorView()
        .preferredColorScheme(.dark)
}

#Preview("Edit Routine") {
    RoutineEditorView(routine: BuiltInRoutines.previewTemplates[0])
        .preferredColorScheme(.dark)
}
