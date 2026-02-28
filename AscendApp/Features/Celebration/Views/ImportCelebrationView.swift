//
//  ImportCelebrationView.swift
//  AscendApp
//

import SwiftUI
import SwiftData

/// Full-screen celebration presented after a successful import
struct ImportCelebrationView: View {
    let data: ImportCelebrationData
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ImportCelebrationViewModel?
    @State private var showingGoalsSheet = false
    @State private var workoutsForGoals: [Workout] = []

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var backgroundGradient: LinearGradient {
        if effectiveColorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color.jet.opacity(0.75),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.95, green: 0.98, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Background
            backgroundGradient
                .ignoresSafeArea()

            Circle()
                .fill(.accent.opacity(effectiveColorScheme == .dark ? 0.12 : 0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 72)
                .offset(y: -210)

            if let viewModel {
                if viewModel.showGoalCompletionScreen {
                    GoalCompletionCelebrationScreen(
                        data: data,
                        buttonOpacity: viewModel.buttonOpacity,
                        onDone: onDismiss
                    )
                    .transition(.opacity)
                } else {
                    StatsCelebrationScreen(
                        viewModel: viewModel,
                        onDone: onDismiss,
                        onSetGoal: { showingGoalsSheet = true }
                    )
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(effectiveColorScheme)
        .sheet(isPresented: $showingGoalsSheet) {
            GoalsSheet(
                isPresented: $showingGoalsSheet,
                workouts: workoutsForGoals,
                onGoalCreated: {
                    // Save action should finish the whole import celebration flow.
                    showingGoalsSheet = false
                    onDismiss()
                }
            )
        }
        .onAppear {
            let vm = ImportCelebrationViewModel(data: data)
            viewModel = vm
            TelemetryManager.shared.log(.celebrationShown)
            workoutsForGoals = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []
            vm.startAnimations()
        }
        .onDisappear {
            viewModel?.cancelAnimations()
        }
    }
}
