import SwiftUI
import SwiftData

struct GoalsSheet: View {
    @Binding var isPresented: Bool
    let workouts: [Workout]
    var onGoalCreated: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared

    @State private var selectedMetric: GoalMetric = .steps
    @State private var targetValue: Int = 10000
    @State private var viewModel = GoalsViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var showingResetInfo = false

    // Progressive disclosure: track if user has interacted
    @State private var hasInteracted = false
    @State private var initialMetric: GoalMetric = .steps
    @State private var initialValue: Int = 10000

    // MARK: - User State

    private enum UserState {
        case brandNew      // A: Zero workouts
        case hasWorkouts   // B: Some workouts, no goal
        case editingGoal   // C: Existing goal being edited
    }

    private var userState: UserState {
        if viewModel.activeGoal != nil {
            return .editingGoal
        } else if workouts.isEmpty {
            return .brandNew
        } else {
            return .hasWorkouts
        }
    }

    // MARK: - Context Line (only shown after interaction)

    private var contextLine: String? {
        guard hasInteracted else { return nil }

        switch userState {
        case .brandNew:
            return starterHeuristic
        case .hasWorkouts:
            return nil
        case .editingGoal:
            return previousGoalContext
        }
    }

    private var starterHeuristic: String {
        switch selectedMetric {
        case .steps:
            return "A good starting target for most people."
        case .floors:
            return "A solid weekly climbing goal."
        case .duration:
            return "Most beginners start around 60–90 minutes per week."
        case .workouts:
            return "3 sessions a week is a strong foundation."
        }
    }

    private var previousGoalContext: String? {
        guard let goal = viewModel.activeGoal else { return nil }
        guard goal.metric == selectedMetric else { return nil }

        switch selectedMetric {
        case .duration:
            let hours = goal.target / 60
            let mins = goal.target % 60
            if hours > 0 && mins > 0 {
                return "Previously: \(hours)h \(mins)m/week"
            } else if hours > 0 {
                return "Previously: \(hours)h/week"
            } else {
                return "Previously: \(mins)m/week"
            }
        default:
            return "Previously: \(goal.target.formatted()) \(goal.metric.unit)/week"
        }
    }

    // MARK: - Computed Properties

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var hasExistingGoal: Bool {
        viewModel.activeGoal != nil
    }

    private var isFormValid: Bool {
        targetValue > 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Question
                Text("What does success look like this week?")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                // Metric Pill Cards
                metricPicker

                // Stepper with progressive context
                stepperSection

                Spacer()
                    .frame(maxHeight: 40)

                // Action Buttons
                actionButtons
            }
            .padding(20)
            .themedBackground()
            .navigationTitle("Weekly Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Cancel")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Weekly Goal")
                            .font(.montserratSemiBold(size: 17))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                        Button {
                            showingResetInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                        }
                    }
                }
            }
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.scrolls)
        .onAppear {
            viewModel.configure(modelContext: modelContext)
            viewModel.loadActiveGoal()

            if let goal = viewModel.activeGoal {
                selectedMetric = goal.metric
                targetValue = goal.target
                initialMetric = goal.metric
                initialValue = goal.target
            } else {
                targetValue = selectedMetric.defaultValue
                initialMetric = selectedMetric
                initialValue = targetValue
            }
        }
        .onChange(of: selectedMetric) { _, newMetric in
            if !hasInteracted && (newMetric != initialMetric) {
                withAnimation(.easeIn(duration: 0.2)) {
                    hasInteracted = true
                }
            }

            if viewModel.activeGoal == nil || viewModel.activeGoal?.metric != newMetric {
                targetValue = newMetric.defaultValue
            } else if let goal = viewModel.activeGoal, goal.metric == newMetric {
                targetValue = goal.target
            }
        }
        .onChange(of: targetValue) { _, newValue in
            if !hasInteracted && (newValue != initialValue) {
                withAnimation(.easeIn(duration: 0.2)) {
                    hasInteracted = true
                }
            }
        }
        .confirmationDialog(
            "Remove Goal",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Goal", role: .destructive) { deleteGoal() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove your current goal?")
        }
        .alert("Reset Schedule", isPresented: $showingResetInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your weekly goal resets every \(viewModel.resetDayFullName) at 12:00 AM (\(viewModel.timeZoneDisplayName)).")
        }
    }

    // MARK: - Metric Picker

    private var metricPicker: some View {
        HStack(spacing: 10) {
            ForEach(GoalMetric.allCases, id: \.self) { metric in
                metricPill(metric)
            }
        }
    }

    private func metricPill(_ metric: GoalMetric) -> some View {
        let isSelected = selectedMetric == metric

        return Button {
            HapticsManager.shared.trigger(.lightImpact)
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMetric = metric
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: metric.icon)
                    .font(.system(size: 15, weight: .medium))
                Text(metric.displayName)
                    .font(.montserratMedium(size: 11))
            }
            .foregroundStyle(isSelected ? .accent : (effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? .accent : .clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? .accent.opacity(0.3) : .clear, radius: 8, x: 0, y: 0)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stepper Section

    private var stepperSection: some View {
        VStack(spacing: 10) {
            // Stepper controls
            HStack(spacing: 20) {
                Button {
                    HapticsManager.shared.trigger(.lightImpact)
                    let newValue = targetValue - selectedMetric.stepAmount
                    if newValue >= selectedMetric.minValue {
                        targetValue = newValue
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(targetValue <= selectedMetric.minValue ? .gray.opacity(0.3) : (effectiveColorScheme == .dark ? .white : .black))
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(targetValue <= selectedMetric.minValue)

                Text(formattedValue)
                    .font(.montserratBold(size: 36))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    .frame(minWidth: 120)
                    .contentTransition(.numericText())

                Button {
                    HapticsManager.shared.trigger(.lightImpact)
                    targetValue += selectedMetric.stepAmount
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }

            // Unit label
            Text(unitLabel)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

            // Context line (fades in after interaction)
            if let context = contextLine {
                Text(context)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: contextLine)
    }

    private var formattedValue: String {
        if selectedMetric == .duration {
            let hours = targetValue / 60
            let minutes = targetValue % 60
            if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
            else if hours > 0 { return "\(hours)h" }
            else { return "\(minutes)m" }
        }
        return targetValue.formatted()
    }

    private var unitLabel: String {
        switch selectedMetric {
        case .steps: return "steps per week"
        case .floors: return "floors per week"
        case .duration: return "per week"
        case .workouts: return targetValue == 1 ? "workout per week" : "workouts per week"
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: createGoal) {
                Text("Save Weekly Goal")
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isFormValid ? .accent : .gray.opacity(0.5))
                    )
            }
            .disabled(!isFormValid)
            .buttonStyle(.plain)

            if hasExistingGoal {
                Button(action: { showingDeleteConfirmation = true }) {
                    Text("Remove Goal")
                        .font(.montserratMedium(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func createGoal() {
        guard targetValue > 0 else { return }
        viewModel.createGoal(metric: selectedMetric, target: targetValue)
        onGoalCreated?()
        isPresented = false
    }

    private func deleteGoal() {
        viewModel.deleteGoal()
        onGoalCreated?()
        isPresented = false
    }
}

// MARK: - Preview

#Preview {
    GoalsSheet(isPresented: .constant(true), workouts: [])
}

#Preview("Dark Mode") {
    GoalsSheet(isPresented: .constant(true), workouts: [])
        .preferredColorScheme(.dark)
}
