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
        FirebaseApp.configure()
        authVM = AuthenticationViewModel()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootView()
            }
        }
        .environment(authVM)
        .modelContainer(createModelContainer())
    }
    
    private func createModelContainer() -> ModelContainer {
        do {
            let config = ModelConfiguration(schema: Schema([Workout.self]))
            return try ModelContainer(for: Workout.self, configurations: config)
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
                let config = ModelConfiguration(schema: Schema([Workout.self]))
                return try ModelContainer(for: Workout.self, configurations: config)
            } catch {
                fatalError("Could not create model container after cleanup: \(error)")
            }
        }
    }
}
