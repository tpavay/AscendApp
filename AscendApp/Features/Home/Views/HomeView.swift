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
    @State private var importService = WorkoutImportService.shared
    @State private var hevyImportService = HevyImportService.shared
    @State private var showingImportSheet = false
    @State private var showingGoalsSheet = false
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
            VStack(spacing: 24) {
                // Header Section
                HStack {
                    Text(greetingWithName)
                        .font(.montserratSemiBold(size: 20))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Spacer()

                    // Notification bell for workout imports
                    NotificationBellView(pendingImports: importService.pendingWorkoutsCount) {
                        Task {
                            await importService.checkForNewWorkouts()
                            showingImportSheet = true
                        }
                    }
                    .onChange(of: importService.pendingWorkoutsCount) { oldValue, newValue in
                        print("🔄 HomeView detected count change from \(oldValue) to \(newValue)")
                    }
                }

                // Main Content Area
                VStack(spacing: 20) {
                    // This Week Card (retrospective - what happened)
                    ThisWeekCard(workouts: workouts)

                    // Weekly Goal Card (intention - what I'm working toward)
                    WeeklyGoalCard(workouts: workouts, showGoalsSheet: $showingGoalsSheet)

                    // Routines Card (guided workouts)
                    RoutinesHomeCard()
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
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

            // Configure the import services with model context
            importService.configure(modelContext: modelContext)
            hevyImportService.configure(modelContext: modelContext)

            // Check for workouts on app launch
            await importService.checkForNewWorkoutsInBackground()

            // Check for new Hevy exercises if connected
            await hevyImportService.checkForNewExercises()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check for new workouts when app comes to foreground (throttled to prevent spam)
            Task {
                await importService.checkForNewWorkoutsInBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            // Reset throttling when app goes to background so next foreground check works
            importService.resetBackgroundCheckThrottle()
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AuthenticationViewModel())
            .environmentObject(TabRouter())
    }
    .modelContainer(for: [Workout.self, Goal.self], inMemory: true)
}
