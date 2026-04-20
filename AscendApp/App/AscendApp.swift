//
//  AscendApp.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import FirebaseCore
import GoogleSignIn
import SwiftUI
import SwiftData

@main
struct AscendApp: App {
    @State private var authVM: AuthenticationViewModel

    init() {
        Self.configureFirebase()
        TelemetryManager.shared.configure()
        TelemetryManager.shared.setAppMetadata()
        authVM = AuthenticationViewModel()
    }

    private static func configureFirebase() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            fatalError("Missing Firebase config: GoogleService-Info.plist")
        }
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootView()
            }
            .onOpenURL { url in
                handleDeepLink(url: url)
            }
        }
        .environment(authVM)
        .environment(NetworkConnectivityService.shared)
        .environment(MediaUploadManager.shared)  // For async media upload status observation
        .modelContainer(createModelContainer())
    }

    private func handleDeepLink(url: URL) {
        // Let Google Sign-In handle its redirect URL
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }

        // Handle Strava OAuth callback
        if url.scheme == "ascendapp" && url.host == "strava-callback" {
            Task { @MainActor in
                StravaManager.shared.handleOAuthCallback(url: url)
            }
        }
    }
    
    private func createModelContainer() -> ModelContainer {
        do {
            let config = ModelConfiguration(schema: Schema([
                Workout.self,
                WorkoutSourceLink.self,
                LeaderboardStats.self,
                PersonalRecord.self,
                Goal.self,
                Routine.self,
                RoutineFolder.self,
                ClimbAttempt.self,
                WeightPersonalRecord.self,
                AggregateWeightRecord.self,
                PendingMediaUpload.self,
                PendingWorkoutDeletion.self
            ]))
            return try ModelContainer(
                for: Workout.self, WorkoutSourceLink.self, LeaderboardStats.self, PersonalRecord.self, Goal.self, Routine.self, RoutineFolder.self, ClimbAttempt.self, WeightPersonalRecord.self, AggregateWeightRecord.self, PendingMediaUpload.self, PendingWorkoutDeletion.self,
                configurations: config
            )
        } catch {
            print("Failed to create model container: \(error)")
            // If migration fails, try deleting all database files and recreating
            do {
                let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

                // Delete all SwiftData/CoreData files
                let filesToDelete = ["default.store", "default.store-shm", "default.store-wal"]
                for fileName in filesToDelete {
                    let fileURL = appSupportURL.appendingPathComponent(fileName)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                        print("Deleted \(fileName)")
                    }
                }

                // Create a clean container
                let config = ModelConfiguration(schema: Schema([
                    Workout.self,
                    WorkoutSourceLink.self,
                    LeaderboardStats.self,
                    PersonalRecord.self,
                    Goal.self,
                    Routine.self,
                    RoutineFolder.self,
                    ClimbAttempt.self,
                    WeightPersonalRecord.self,
                    AggregateWeightRecord.self,
                    PendingMediaUpload.self,
                    PendingWorkoutDeletion.self
                ]))
                return try ModelContainer(
                    for: Workout.self, WorkoutSourceLink.self, LeaderboardStats.self, PersonalRecord.self, Goal.self, Routine.self, RoutineFolder.self, ClimbAttempt.self, WeightPersonalRecord.self, AggregateWeightRecord.self, PendingMediaUpload.self, PendingWorkoutDeletion.self,
                    configurations: config
                )
            } catch {
                fatalError("Could not create model container after cleanup: \(error)")
            }
        }
    }
}
