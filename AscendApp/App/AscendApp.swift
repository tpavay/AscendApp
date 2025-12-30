//
//  AscendApp.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import FirebaseCore
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
        #if DEBUG
        let configFile = "GoogleService-Info-Dev"
        #elseif STAGING
        let configFile = "GoogleService-Info-Staging"
        #else
        let configFile = "GoogleService-Info-Production"
        #endif

        guard let filePath = Bundle.main.path(forResource: configFile, ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: filePath) else {
            fatalError("Missing Firebase config: \(configFile).plist")
        }
        FirebaseApp.configure(options: options)
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
        .modelContainer(createModelContainer())
    }

    private func handleDeepLink(url: URL) {
        // Handle Strava OAuth callback
        if url.scheme == "ascendapp" && url.host == "strava-callback" {
            Task { @MainActor in
                StravaManager.shared.handleOAuthCallback(url: url)
            }
        }
    }
    
    private func createModelContainer() -> ModelContainer {
        do {
            let config = ModelConfiguration(schema: Schema([Workout.self, LeaderboardStats.self, PersonalRecord.self, Goal.self, Routine.self, RoutineFolder.self]))
            return try ModelContainer(for: Workout.self, LeaderboardStats.self, PersonalRecord.self, Goal.self, Routine.self, RoutineFolder.self, configurations: config)
        } catch {
            print("❌ Failed to create model container: \(error)")
            // If migration fails, try deleting all database files and recreating
            do {
                let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

                // Delete all SwiftData/CoreData files
                let filesToDelete = ["default.store", "default.store-shm", "default.store-wal"]
                for fileName in filesToDelete {
                    let fileURL = appSupportURL.appendingPathComponent(fileName)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                        print("🗑️ Deleted \(fileName)")
                    }
                }

                // Create a clean container
                let config = ModelConfiguration(schema: Schema([Workout.self, LeaderboardStats.self, PersonalRecord.self, Goal.self, Routine.self, RoutineFolder.self]))
                return try ModelContainer(for: Workout.self, LeaderboardStats.self, PersonalRecord.self, Goal.self, Routine.self, RoutineFolder.self, configurations: config)
            } catch {
                fatalError("Could not create model container after cleanup: \(error)")
            }
        }
    }
}
