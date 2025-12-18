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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.montserratRegular(size: 18))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .gray)

                        Text(authVM.displayName.isEmpty ? "User" : authVM.displayName)
                            .font(.montserratBold(size: 28))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                    }

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
                    // Streak & Activity Section
                    StreakView(workouts: workouts)

                    // Weekly Goal Section
                    GoalsCard(workouts: workouts, showGoalsSheet: $showingGoalsSheet)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Last 7 Days")
                            .font(.montserratSemiBold(size: 20))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)

                        LastSevenDaysSummaryCard(workouts: workouts)
                    }
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
            GoalsSheet(isPresented: $showingGoalsSheet)
                .presentationDetents([.medium, .large])
        }
        .task {
            // Set first launch date if not already set
            if firstLaunchDate == 0 {
                firstLaunchDate = Date().timeIntervalSince1970
            }

            // Configure the import service with model context
            importService.configure(modelContext: modelContext)

            // Check for workouts on app launch
            await importService.checkForNewWorkoutsInBackground()
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
