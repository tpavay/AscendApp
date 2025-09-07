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

    var body: some View {
        VStack(spacing: 24) {
            // Header Section
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome")
                        .font(.montserratRegular(size: 18))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .gray)
                    
                    Text(authVM.displayName.isEmpty ? "User" : authVM.displayName)
                        .font(.montserratBold(size: 28))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                }
                
                Spacer()
                
                // Notification bell for workout imports
                NotificationBellView(pendingImports: importService.pendingWorkoutsCount) {
                    showingImportSheet = true
                }
            }
            
            // Main Content Area
            VStack(spacing: 20) {
                // Streak & Activity Section
                StreakView(workouts: workouts)
            }
            
            Spacer()
        }
        .padding(20)
        .themedBackground()
        .sheet(isPresented: $showingImportSheet) {
            WorkoutImportSheet()
        }
        .task {
            // Configure the import service with model context
            importService.configure(modelContext: modelContext)
            
            // Check for new workouts on app launch
            await importService.checkForNewWorkouts()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check for new workouts when app comes to foreground
            Task {
                await importService.checkForNewWorkouts()
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AuthenticationViewModel())
    }
    .modelContainer(for: Workout.self, inMemory: true)
}
