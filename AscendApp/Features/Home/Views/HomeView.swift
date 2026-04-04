//
//  HomeView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @State private var importCoordinator = WorkoutImportCoordinator.shared
    @State private var showingImportSheet = false
    @State private var showingGoalsSheet = false
    @State private var showingWorkoutEntrySheet = false
    @State private var showingWorkoutForm = false
    @State private var showingCompletedView = false
    @State private var completedWorkout: Workout?
    @State private var showingClimbBrowse = false
    @State private var showingRoutinesView = false
    @State private var selectedHomeClimb: Climb?
    @State private var globeViewModel = GlobeViewModel()
    @AppStorage("firstLaunchDate") private var firstLaunchDate: Double = 0

    private var greeting: String {
        // If first launch date not set, this is the first launch
        if firstLaunchDate == 0 {
            return "Welcome"
        }

        let firstDate = Date(timeIntervalSince1970: firstLaunchDate)
        let isFirstDay = Calendar.current.isDate(firstDate, inSameDayAs: Date())

        if isFirstDay {
            return "Welcome"
        }

        // Time-based greeting
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    private var greetingWithName: String {
        if authVM.displayName.isEmpty {
            return greeting
        }
        // Use just the first name (first part before space)
        let firstName = authVM.displayName.split(separator: " ").first.map(String.init) ?? authVM.displayName
        return "\(greeting), \(firstName)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text(greetingWithName)
                        .font(.montserratSemiBold(size: 20))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Spacer()

                    // Notification bell for workout imports
                    NotificationBellView(pendingImports: importCoordinator.pendingCount) {
                        Task {
                            await importCoordinator.refreshPendingImports(trigger: .manualReview)
                            showingImportSheet = true
                        }
                    }
                    .onChange(of: importCoordinator.pendingCount) { oldValue, newValue in
                        print("🔄 HomeView detected count change from \(oldValue) to \(newValue)")
                    }
                }

                VStack(spacing: 20) {
                    HomeLogWorkoutButton {
                        showingWorkoutEntrySheet = true
                    }

                    ThisWeekCard(workouts: workouts)

                    WeeklyGoalCard(workouts: workouts, showGoalsSheet: $showingGoalsSheet)

                    ClimbCardView(
                        viewModel: globeViewModel,
                        onBrowse: {
                            showingClimbBrowse = true
                        },
                        onOpenClimb: { climb in
                            selectedHomeClimb = climb
                        }
                    )

                    RoutinesHomeCard()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.top, 8)
        .themedBackground()
        .navigationDestination(item: $selectedHomeClimb) { climb in
            ClimbDetailView(climb: climb)
        }
        .navigationDestination(isPresented: $showingClimbBrowse) {
            ClimbBrowseView(viewModel: globeViewModel)
        }
        .navigationDestination(isPresented: $showingRoutinesView) {
            RoutinesView()
        }
        .sheet(isPresented: $showingWorkoutEntrySheet) {
            HomeWorkoutActionSheet(
                onManualEntry: presentWorkoutForm,
                onStartRoutine: presentRoutines,
                onImportWorkouts: presentImportSheet,
                pendingImportCount: importCoordinator.pendingCount
            )
            .appSheetStyle(.fitted())
        }
        .sheet(isPresented: $showingWorkoutForm) {
            WorkoutFormView(
                showingWorkoutForm: $showingWorkoutForm,
                onWorkoutCompleted: { workout in
                    completedWorkout = workout
                    showingWorkoutForm = false

                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        showingCompletedView = true
                    }
                }
            )
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showingCompletedView) {
            if let completedWorkout {
                WorkoutShareCarouselView(
                    workout: completedWorkout,
                    workoutCount: workouts.count,
                    onDismiss: {
                        showingCompletedView = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            WorkoutImportSheet()
        }
        .sheet(isPresented: $showingGoalsSheet) {
            GoalsSheet(isPresented: $showingGoalsSheet, workouts: workouts)
        }
        .task {
            // Set first launch date if not already set
            if firstLaunchDate == 0 {
                firstLaunchDate = Date().timeIntervalSince1970
            }

            // Configure the unified import service with model context
            importCoordinator.configure(modelContext: modelContext)
            globeViewModel.loadIfNeeded(modelContext: modelContext)

            // Check for workouts from all sources on app launch
            await importCoordinator.refreshPendingImports(trigger: .automatic)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check for new workouts when app comes to foreground (throttled to prevent spam)
            Task {
                await importCoordinator.refreshPendingImports(trigger: .automatic)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbStateDidChange)) { _ in
            globeViewModel.refresh(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .climbCatalogDidChange)) { _ in
            globeViewModel.reloadCatalog(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            // Reset throttling when app goes to background so next foreground check works
            importCoordinator.resetAutomaticCheckThrottle()
        }
    }

    private func presentWorkoutForm() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showingWorkoutForm = true
        }
    }

    private func presentRoutines() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            showingRoutinesView = true
        }
    }

    private func presentImportSheet() {
        showingWorkoutEntrySheet = false

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await importCoordinator.refreshPendingImports(trigger: .manualReview)
            showingImportSheet = true
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AuthenticationViewModel())
            .environment(TabRouter())
    }
    .modelContainer(
        for: [
            Workout.self,
            WorkoutSourceLink.self,
            Goal.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self
        ],
        inMemory: true
    )
}
