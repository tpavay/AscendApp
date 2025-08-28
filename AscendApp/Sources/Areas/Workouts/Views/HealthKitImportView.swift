//
//  HealthKitImportView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI
import SwiftData
import HealthKit

struct HealthKitImportView: View {
    let onComplete: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @StateObject private var healthKitService = HealthKitService.shared
    
    init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }
    
    @State private var importState: ImportState = .checkingPermission
    @State private var foundWorkouts: [HKWorkout] = []
    @State private var importedCount = 0
    @State private var errorMessage: String?
    
    enum ImportState {
        case checkingPermission
        case needsPermission
        case permissionDenied
        case fetchingWorkouts
        case workoutsFound
        case importing
        case completed
        case error
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.accent)
                    
                    Spacer()
                    
                    Text("Apple Health Import")
                        .font(.montserratBold(size: 18))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    // Invisible button for balance
                    Button("") { }
                        .font(.montserratMedium(size: 16))
                        .foregroundStyle(.clear)
                        .disabled(true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                
                // Content based on state
                ScrollView {
                    VStack(spacing: 24) {
                        switch importState {
                        case .checkingPermission:
                            CheckingPermissionView()
                        case .needsPermission:
                            NeedsPermissionView {
                                await requestPermission()
                            }
                        case .permissionDenied:
                            PermissionDeniedView()
                        case .fetchingWorkouts:
                            FetchingWorkoutsView()
                        case .workoutsFound:
                            WorkoutsFoundView(workouts: foundWorkouts) {
                                await importWorkouts()
                            }
                        case .importing:
                            ImportingView(progress: importedCount, total: foundWorkouts.count)
                        case .completed:
                            ImportCompletedView(importedCount: importedCount) {
                                onComplete?() ?? dismiss()
                            }
                        case .error:
                            ErrorView(message: errorMessage ?? "An unknown error occurred") {
                                await checkPermissionAndFetchWorkouts()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .themedBackground()
            .task {
                await checkPermissionAndFetchWorkouts()
            }
        }
    }
    
    private func checkPermissionAndFetchWorkouts() async {
        importState = .checkingPermission
        
        guard healthKitService.isHealthDataAvailable else {
            errorMessage = "Health data is not available on this device"
            importState = .error
            return
        }
        
        let hasPermission = await healthKitService.requestPermission()
        
        if hasPermission {
            await fetchWorkouts()
        } else {
            importState = .needsPermission
        }
    }
    
    private func requestPermission() async {
        let granted = await healthKitService.requestPermission()
        
        if granted {
            await fetchWorkouts()
        } else {
            importState = .permissionDenied
        }
    }
    
    private func fetchWorkouts() async {
        importState = .fetchingWorkouts
        
        let workouts = await healthKitService.fetchStairStepperWorkouts()
        foundWorkouts = workouts
        
        if workouts.isEmpty {
            errorMessage = "No stair stepper workouts found in Apple Health"
            importState = .error
        } else {
            importState = .workoutsFound
        }
    }
    
    private func importWorkouts() async {
        importState = .importing
        importedCount = 0
        
        for hkWorkout in foundWorkouts {
            let metrics = await healthKitService.fetchWorkoutMetrics(for: hkWorkout)
            let workout = hkWorkout.toAscendWorkout(with: metrics)
            
            modelContext.insert(workout)
            importedCount += 1
        }
        
        do {
            try modelContext.save()
            importState = .completed
        } catch {
            errorMessage = "Failed to save workouts: \(error.localizedDescription)"
            importState = .error
        }
    }
}

// MARK: - State Views

struct CheckingPermissionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Checking Health permissions...")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .frame(maxHeight: .infinity)
    }
}

struct NeedsPermissionView: View {
    let onRequestPermission: () async -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var isRequesting = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.red)
            
            VStack(spacing: 12) {
                Text("Health Access Required")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                VStack(spacing: 12) {
                    Text("To import your stair climbing workouts, we need permission to read your Health data. We'll access:")
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .multilineTextAlignment(.center)
                    
                    Text("Note: Even if you've granted permission in Settings, we need to request it directly through HealthKit to refresh the authorization.")
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .italic()
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                PermissionItem(icon: "figure.stair.stepper", text: "Workouts")
                PermissionItem(icon: "figure.walk", text: "Steps")
                PermissionItem(icon: "heart", text: "Heart Rate")
                PermissionItem(icon: "flame", text: "Active Calories")
                PermissionItem(icon: "flame.fill", text: "Resting Calories")
            }
            .padding(.horizontal, 16)
            
            Button(action: {
                Task {
                    isRequesting = true
                    await onRequestPermission()
                    isRequesting = false
                }
            }) {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Grant Access")
                    }
                }
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.accent)
                )
            }
            .disabled(isRequesting)
        }
    }
}

struct PermissionItem: View {
    let icon: String
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.accent)
                .frame(width: 20)
            
            Text(text)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Spacer()
        }
    }
}

struct PermissionDeniedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.orange)
            
            VStack(spacing: 12) {
                Text("Settings Required")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                VStack(spacing: 16) {
                    Text("Since the HealthKit permission dialog didn't appear, please manually enable permissions in Settings:")
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open Settings app")
                        Text("2. Go to Privacy & Security > Health")  
                        Text("3. Tap 'AscendApp'")
                        Text("4. Enable all data categories")
                        Text("5. Return to this app and try again")
                    }
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                    
                    Button("Open Health Settings") {
                        // Try to open the Health app settings directly
                        if let healthUrl = URL(string: "x-apple-health://"),
                           UIApplication.shared.canOpenURL(healthUrl) {
                            UIApplication.shared.open(healthUrl)
                        } else if let settingsUrl = URL(string: "App-prefs:Privacy&path=HEALTH") {
                            UIApplication.shared.open(settingsUrl)
                        } else {
                            // Fallback to general settings
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        }
                    }
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.accent)
                    )
                }
            }
        }
    }
}

struct FetchingWorkoutsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Searching for workouts...")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .frame(maxHeight: .infinity)
    }
}

struct WorkoutsFoundView: View {
    let workouts: [HKWorkout]
    let onImport: () async -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var isImporting = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.green)
            
            VStack(spacing: 12) {
                Text("Workouts Found")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Found \(workouts.count) stair climbing workout\(workouts.count == 1 ? "" : "s") ready to import")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                Task {
                    isImporting = true
                    await onImport()
                    isImporting = false
                }
            }) {
                HStack {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Import \(workouts.count) Workout\(workouts.count == 1 ? "" : "s")")
                    }
                }
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.accent)
                )
            }
            .disabled(isImporting)
        }
    }
}

struct ImportingView: View {
    let progress: Int
    let total: Int
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(progress), total: Double(total))
                .frame(height: 8)
            
            Text("Importing workouts... \(progress)/\(total)")
                .font(.montserratMedium(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
        }
        .frame(maxHeight: .infinity)
    }
}

struct ImportCompletedView: View {
    let importedCount: Int
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.green)
            
            VStack(spacing: 12) {
                Text("Import Complete")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text("Successfully imported \(importedCount) workout\(importedCount == 1 ? "" : "s") from Apple Health")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onDismiss) {
                Text("Done")
                    .font(.montserratMedium(size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.accent)
                    )
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () async -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var isRetrying = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.red)
            
            VStack(spacing: 12) {
                Text("Import Failed")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Text(message)
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                Task {
                    isRetrying = true
                    await onRetry()
                    isRetrying = false
                }
            }) {
                HStack {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Try Again")
                    }
                }
                .font(.montserratMedium(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.accent)
                )
            }
            .disabled(isRetrying)
        }
    }
}

#Preview {
    HealthKitImportView(onComplete: nil)
        .modelContainer(for: Workout.self, inMemory: true)
}