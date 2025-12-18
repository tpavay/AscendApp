import SwiftUI
import SwiftData

struct GoalsSheet: View {
    @Binding var isPresented: Bool
    var onGoalCreated: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared

    @State private var selectedMetric: GoalMetric = .steps
    @State private var targetValue: String = ""
    @State private var viewModel = GoalsViewModel()
    @State private var showingDeleteConfirmation = false

    @FocusState private var isTargetFocused: Bool

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var hasExistingGoal: Bool {
        viewModel.activeGoal != nil
    }

    private var isFormValid: Bool {
        guard let value = Int(targetValue), value > 0 else {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Metric Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("What do you want to track?")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(GoalMetric.allCases, id: \.self) { metric in
                            Text(metric.displayName).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Target Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Weekly target")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    HStack {
                        TextField("Enter target", text: $targetValue)
                            .focused($isTargetFocused)
                            .keyboardType(.numberPad)
                            .font(.montserratRegular(size: 18))
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5), lineWidth: 1)
                            )

                        Text(selectedMetric.unit)
                            .font(.montserratMedium(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }

                    // Duration hint
                    if selectedMetric == .duration {
                        Text("Enter target in minutes")
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.7))
                    }
                }

                // Reset Info Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.accent)

                        Text("Repeats: Weekly")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }

                    Text("Resets every \(viewModel.resetDayFullName) at 12:00 AM (\(viewModel.timeZoneDisplayName))")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                        )
                )

                // Replace warning (if existing goal)
                if hasExistingGoal {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)

                        Text("This will replace your current goal")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 4)
                }

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    // Set Goal Button
                    Button(action: createGoal) {
                        Text(hasExistingGoal ? "Replace Goal" : "Set Goal")
                            .font(.montserratSemiBold(size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isFormValid ? .accent : .gray.opacity(0.5))
                            )
                    }
                    .disabled(!isFormValid)
                    .buttonStyle(.plain)

                    // Delete Goal Button (if existing goal)
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
            .padding(20)
            .themedBackground()
            .navigationTitle(hasExistingGoal ? "Edit Goal" : "Set a Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .keyboard) {
                    KeyboardDismissButton()
                }
            }
        }
        .onAppear {
            viewModel.configure(modelContext: modelContext)
            viewModel.loadActiveGoal()

            // Pre-fill if editing existing goal
            if let goal = viewModel.activeGoal {
                selectedMetric = goal.metric
                targetValue = "\(goal.target)"
            }
        }
        .confirmationDialog(
            "Remove Goal",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Goal", role: .destructive) {
                deleteGoal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove your current goal?")
        }
    }

    private func createGoal() {
        guard let target = Int(targetValue), target > 0 else { return }

        viewModel.createGoal(metric: selectedMetric, target: target)
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
    GoalsSheet(isPresented: .constant(true))
}

#Preview("Dark Mode") {
    GoalsSheet(isPresented: .constant(true))
        .preferredColorScheme(.dark)
}
