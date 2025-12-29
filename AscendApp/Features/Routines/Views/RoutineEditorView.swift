import SwiftUI
import SwiftData

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    @State private var viewModel = RoutineEditorViewModel()
    @State private var showIntervalEditor = false
    @State private var editingIntervalIndex: Int?
    @State private var showSaveError = false
    @FocusState private var isTextFieldFocused: Bool
    @State private var draggingInterval: RoutineInterval?

    let routine: Routine?
    var onSave: ((Routine) -> Void)?

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    init(routine: Routine? = nil, onSave: ((Routine) -> Void)? = nil) {
        self.routine = routine
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    nameSection
                    descriptionSection
                    difficultySection
                    defaultWeightsSection
                    intervalsSection
                }
                .padding(20)
            }
            .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.accent)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRoutine()
                    }
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(viewModel.canSave ? .accent : .gray)
                    .disabled(!viewModel.canSave)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextFieldFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
                }
            }
            .sheet(isPresented: $showIntervalEditor) {
                if let index = editingIntervalIndex {
                    IntervalEditorSheet(interval: viewModel.intervals[index]) { updatedInterval in
                        viewModel.updateInterval(at: index, with: updatedInterval)
                        editingIntervalIndex = nil
                    }
                    .presentationDetents([.large])
                } else {
                    IntervalEditorSheet { newInterval in
                        viewModel.addInterval(newInterval)
                    }
                    .presentationDetents([.large])
                }
            }
            .alert("Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Failed to save routine.")
            }
        }
        .onAppear {
            viewModel.configure(modelContext: modelContext, routine: routine)
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Name")

            TextField("Routine name", text: $viewModel.name)
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .padding(16)
                .background(fieldBackground)
                .focused($isTextFieldFocused)
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Description (Optional)")

            TextField("What's this routine about?", text: $viewModel.routineDescription, axis: .vertical)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .lineLimit(3...6)
                .padding(16)
                .background(fieldBackground)
                .focused($isTextFieldFocused)
        }
    }

    // MARK: - Difficulty Section

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Difficulty (Optional)")

            VStack(spacing: 12) {
                HStack {
                    Text("Difficulty Level")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                    Spacer()

                    Text(difficultyLabel)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(difficultyColor)
                }

                Picker("Difficulty", selection: $viewModel.difficulty) {
                    Text("Custom").tag(Int?.none)
                    Text("Easy").tag(Int?.some(1))
                    Text("Light").tag(Int?.some(2))
                    Text("Moderate").tag(Int?.some(3))
                    Text("Hard").tag(Int?.some(4))
                    Text("Intense").tag(Int?.some(5))
                }
                .pickerStyle(.segmented)
            }
            .padding(16)
            .background(fieldBackground)
        }
    }

    private var difficultyLabel: String {
        guard let level = viewModel.difficulty else { return "Custom" }
        switch level {
        case 1: return "Easy"
        case 2: return "Light"
        case 3: return "Moderate"
        case 4: return "Hard"
        case 5: return "Intense"
        default: return "Custom"
        }
    }

    private var difficultyColor: Color {
        guard let level = viewModel.difficulty else { return .accent }
        switch level {
        case 1: return .green
        case 2: return .teal
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .accent
        }
    }

    // MARK: - Default Weights Section

    private var defaultWeightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Default Weights (Optional)")

            VStack(alignment: .leading, spacing: 12) {
                Text("Configure weights that apply to all intervals by default. Individual intervals can override these settings.")
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    .padding(.horizontal, 4)

                WeightEntryView(
                    configuration: $viewModel.defaultWeightConfiguration,
                    measurementSystem: settingsManager.measurementSystem
                )
            }
        }
    }

    // MARK: - Intervals Section

    private var intervalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Intervals")

                Spacer()

                if !viewModel.intervals.isEmpty {
                    Text(viewModel.totalDurationFormatted)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.accent)
                }
            }

            if viewModel.intervals.isEmpty {
                emptyIntervalsState
            } else {
                intervalsList
            }

            addIntervalButton
        }
    }

    private var emptyIntervalsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))

            Text("No intervals yet")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)

            Text("Add intervals to build your routine")
                .font(.montserratRegular(size: 12))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(fieldBackground)
    }

    private var intervalsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.intervals.enumerated()), id: \.element.id) { index, interval in
                intervalRow(interval: interval, index: index)
                    .draggable(interval.id.uuidString) {
                        // Drag preview
                        IntervalEditorRow(interval: interval, index: index + 1)
                            .frame(width: 300)
                            .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 8)
                            .onAppear {
                                draggingInterval = interval
                                HapticsManager.shared.trigger(.mediumImpact)
                            }
                    }
                    .dropDestination(for: String.self) { items, location in
                        guard let draggedId = items.first,
                              let sourceIndex = viewModel.intervals.firstIndex(where: { $0.id.uuidString == draggedId }),
                              sourceIndex != index else {
                            return false
                        }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.moveInterval(from: IndexSet(integer: sourceIndex), to: sourceIndex < index ? index + 1 : index)
                        }
                        HapticsManager.shared.trigger(.lightImpact)
                        return true
                    } isTargeted: { isTargeted in
                        // Optional: could add visual feedback when dragging over
                    }
                    .opacity(draggingInterval?.id == interval.id ? 0.5 : 1.0)
            }
        }
        .background(fieldBackground)
        .onDrop(of: [.text], isTargeted: nil) { _ in
            draggingInterval = nil
            return false
        }
    }

    @ViewBuilder
    private func intervalRow(interval: RoutineInterval, index: Int) -> some View {
        VStack(spacing: 0) {
            IntervalEditorRow(
                interval: interval,
                index: index + 1,
                onEdit: {
                    editingIntervalIndex = index
                    showIntervalEditor = true
                },
                onDuplicate: {
                    viewModel.duplicateInterval(at: index)
                    HapticsManager.shared.trigger(.lightImpact)
                },
                onDelete: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.deleteInterval(at: index)
                    }
                    HapticsManager.shared.trigger(.lightImpact)
                }
            )

            if index < viewModel.intervals.count - 1 {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }

    private var addIntervalButton: some View {
        Button {
            editingIntervalIndex = nil
            showIntervalEditor = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Add Interval")
                    .font(.montserratMedium(size: 14))
            }
            .foregroundStyle(.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.accent.opacity(0.5), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.accent.opacity(0.05))
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.montserratMedium(size: 12))
            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
            .padding(.leading, 4)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
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
}

// MARK: - Interval Editor Row

struct IntervalEditorRow: View {
    let interval: RoutineInterval
    let index: Int
    var onEdit: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Index circle
            Text("\(index)")
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(.accent)
                )

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(interval.intensityDisplay)
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text("•")
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))

                    Text(interval.durationFormatted)
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }

                if interval.modifiers.hasAnyActive {
                    Text(interval.modifiers.activeModifiers.joined(separator: " • "))
                        .font(.montserratRegular(size: 11))
                        .foregroundStyle(.accent.opacity(0.8))
                }
            }

            Spacer()

            // Actions menu
            Menu {
                Button(action: { onEdit?() }) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(action: { onDuplicate?() }) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive, action: { onDelete?() }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit?()
        }
    }
}

#Preview("New Routine") {
    RoutineEditorView()
}

#Preview("Edit Routine") {
    RoutineEditorView(routine: BuiltInRoutines.beginner20Min)
}

#Preview("Dark Mode") {
    RoutineEditorView()
        .preferredColorScheme(.dark)
}
