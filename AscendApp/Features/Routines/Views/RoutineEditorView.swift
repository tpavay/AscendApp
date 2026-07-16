import SwiftUI
import SwiftData

private enum RoutineEditorField: Hashable {
    case name
    case description
}

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var viewModel = RoutineEditorViewModel()
    @State private var showSaveError = false
    @State private var draggingIntervalId: UUID?
    @FocusState private var focusedField: RoutineEditorField?

    let routine: Routine?
    let folderId: UUID?
    var onSave: ((Routine) -> Void)?

    init(routine: Routine? = nil, folderId: UUID? = nil, onSave: ((Routine) -> Void)? = nil) {
        self.routine = routine
        self.folderId = folderId
        self.onSave = onSave
    }

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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

                    RoutineEditorPreviewCard(
                        intervals: viewModel.previewIntervals,
                        ghostInterval: viewModel.previewGhostInterval
                    )

                    if !viewModel.displayedIntervals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            RoutineEditorSectionLabel(text: "Intervals")

                            LazyVStack(spacing: 10) {
                                ForEach(viewModel.displayedIntervals) { interval in
                                    VStack(spacing: 10) {
                                        RoutineEditorIntervalRow(
                                            interval: interval,
                                            isSelected: viewModel.selectedInterval?.id == interval.id,
                                            onTap: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    viewModel.selectInterval(interval)
                                                }
                                            }
                                        )
                                        .draggable(interval.id.uuidString) {
                                            RoutineEditorIntervalRow(
                                                interval: interval,
                                                isSelected: false,
                                                onTap: {}
                                            )
                                            .frame(width: 320)
                                            .onAppear {
                                                draggingIntervalId = interval.id
                                                HapticsManager.shared.trigger(.lightImpact)
                                            }
                                        }
                                        .dropDestination(for: String.self) { items, _ in
                                            guard let rawValue = items.first,
                                                  let draggedId = UUID(uuidString: rawValue) else {
                                                return false
                                            }

                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                viewModel.moveInterval(withId: draggedId, before: interval.id)
                                            }
                                            draggingIntervalId = nil
                                            HapticsManager.shared.trigger(.lightImpact)
                                            return true
                                        }
                                        .opacity(draggingIntervalId == interval.id ? 0.5 : 1)

                                        if viewModel.selectedInterval?.id == interval.id {
                                            builderCard
                                                .id(builderAnchorId(for: interval.id))
                                                .transition(.move(edge: .top).combined(with: .opacity))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !viewModel.isEditingInterval {
                        builderCard
                    }

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
            .onChange(of: viewModel.selectedInterval?.id) { _, selectedIntervalId in
                guard let selectedIntervalId else { return }

                Task {
                    try await Task.sleep(for: .milliseconds(80))
                    withAnimation(.easeInOut(duration: 0.24)) {
                        scrollProxy.scrollTo(builderAnchorId(for: selectedIntervalId), anchor: .center)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keyboardDoneToolbar {
            focusedField = nil
        }
        .alert("Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Failed to save routine.")
        }
        .onAppear {
            viewModel.configure(modelContext: modelContext, routine: routine, folderId: folderId)
        }
        .onChange(of: focusedField) {
            if focusedField == nil {
                draggingIntervalId = nil
            }
        }
        .appSheetBackground()
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

    @ViewBuilder
    private var builderCard: some View {
        RoutineIntervalBuilderCard(
            level: $viewModel.draftLevel,
            duration: $viewModel.draftDuration,
            stepType: $viewModel.draftStepType,
            isEditing: viewModel.isEditingInterval,
            onCommit: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.commitDraftInterval()
                }
            },
            onCancelEdit: viewModel.isEditingInterval ? {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.cancelEditingInterval()
                }
            } : nil,
            onDelete: viewModel.isEditingInterval ? {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.deleteSelectedInterval()
                }
            } : nil
        )
    }

    private func builderAnchorId(for intervalId: UUID) -> String {
        "routine-editor-builder-\(intervalId.uuidString)"
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

private struct RoutineEditorNameField: View {
    @Binding var text: String
    let focusedField: FocusState<RoutineEditorField?>.Binding

    var body: some View {
        TextField("", text: $text, prompt: Text("Routine name").foregroundStyle(.white.opacity(0.2)))
            .font(.montserratMedium(size: 17))
            .foregroundStyle(.white)
            .focused(focusedField, equals: .name)
            .padding(.horizontal, 16)
            .frame(height: 78)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.jetLighter.opacity(0.65))
            )
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
