//
//  SettingsManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var isResettingAfterAccountDeletion = false
    
    private let measurementSystemKey = "measurementSystem"
    private let stepHeightKey = "stepHeight"
    private let fitnessLevelKey = "userFitnessLevel"
    private let seededBaseLevelKey = "seededBaseLevel"
    private let autoCalculatedBaseLevelKey = "autoCalculatedBaseLevel"
    private let manualBaseLevelOverrideKey = "manualBaseLevelOverride"
    private let hasCompletedBaseLevelOnboardingKey = "hasCompletedBaseLevelOnboarding"
    private let firstLaunchDateKey = "firstLaunchDate"
    private let appleHealthAutoImportEnabledKey = "appleHealthAutoImportEnabled"
    private let appleHealthAutoImportActivatedAtKey = "appleHealthAutoImportActivatedAt"
    private let appleHealthAutoImportPromptDismissedUserIDsKey = "appleHealthAutoImportPromptDismissedUserIDs"
    var measurementSystem: MeasurementSystem {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            let oldSystem = oldValue
            saveMeasurementSystem()
            // Convert step height to new measurement system
            convertStepHeight(from: oldSystem, to: measurementSystem)
        }
    }
    
    var stepHeight: Double {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            saveStepHeight()
        }
    }
    
    var fitnessLevel: FitnessLevel {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            saveFitnessLevel()
        }
    }

    var seededBaseLevel: Int {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            saveSeededBaseLevel()
        }
    }

    var autoCalculatedBaseLevel: Int? {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            saveAutoCalculatedBaseLevel()
        }
    }

    var manualBaseLevelOverride: Int? {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            saveManualBaseLevelOverride()
        }
    }

    var hasCompletedBaseLevelOnboarding: Bool {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            saveHasCompletedBaseLevelOnboarding()
        }
    }

    var appleHealthAutoImportEnabled: Bool {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            if appleHealthAutoImportEnabled && !oldValue {
                appleHealthAutoImportActivatedAt = Date()
            } else if !appleHealthAutoImportEnabled {
                appleHealthAutoImportActivatedAt = nil
            }

            saveAppleHealthAutoImportEnabled()
        }
    }

    var appleHealthAutoImportActivatedAt: Date? {
        didSet {
            guard !isResettingAfterAccountDeletion else { return }
            saveAppleHealthAutoImportActivatedAt()
        }
    }

    var effectiveBaseLevel: Int {
        manualBaseLevelOverride ?? autoCalculatedBaseLevel ?? seededBaseLevel
    }

    var effectiveBaseLevelSPM: Int {
        SPMMappingService.spm(forLevel: effectiveBaseLevel)
    }

    var baseLevelState: BaseLevelState {
        if manualBaseLevelOverride != nil {
            return .manualOverride
        }

        if autoCalculatedBaseLevel != nil {
            return .autoCalculated
        }

        return .seeded
    }

    var shouldPresentBaseLevelOnboarding: Bool {
        !hasCompletedBaseLevelOnboarding
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load saved measurement system or default to imperial
        let loadedMeasurementSystem: MeasurementSystem
        if let savedSystem = userDefaults.string(forKey: measurementSystemKey),
           let system = MeasurementSystem(rawValue: savedSystem) {
            loadedMeasurementSystem = system
        } else {
            loadedMeasurementSystem = .imperial
        }
        self.measurementSystem = loadedMeasurementSystem
        
        // Load saved step height or default based on measurement system
        if userDefaults.object(forKey: stepHeightKey) != nil {
            self.stepHeight = userDefaults.double(forKey: stepHeightKey)
        } else {
            self.stepHeight = loadedMeasurementSystem.defaultStepHeight
        }
        
        // Load saved fitness level or default to intermediate
        let loadedFitnessLevel: FitnessLevel
        if let savedLevel = userDefaults.string(forKey: fitnessLevelKey),
           let level = FitnessLevel(rawValue: savedLevel) {
            loadedFitnessLevel = level
        } else {
            loadedFitnessLevel = .intermediate
        }
        self.fitnessLevel = loadedFitnessLevel

        let hadPreviousLaunch = userDefaults.object(forKey: firstLaunchDateKey) != nil
        let migratedSeededLevel = Self.migratedBaseLevel(for: loadedFitnessLevel)
        if let storedSeededBaseLevel = userDefaults.object(forKey: seededBaseLevelKey) as? Int {
            self.seededBaseLevel = SPMMappingService.clampedLevel(storedSeededBaseLevel)
        } else {
            let initialSeededBaseLevel = hadPreviousLaunch ? migratedSeededLevel : 7
            self.seededBaseLevel = initialSeededBaseLevel
            userDefaults.set(initialSeededBaseLevel, forKey: seededBaseLevelKey)
        }

        if let storedAutoCalculatedBaseLevel = userDefaults.object(forKey: autoCalculatedBaseLevelKey) as? Int {
            self.autoCalculatedBaseLevel = SPMMappingService.clampedLevel(storedAutoCalculatedBaseLevel)
        } else {
            self.autoCalculatedBaseLevel = nil
        }

        if let storedManualBaseLevelOverride = userDefaults.object(forKey: manualBaseLevelOverrideKey) as? Int {
            self.manualBaseLevelOverride = SPMMappingService.clampedLevel(storedManualBaseLevelOverride)
        } else {
            self.manualBaseLevelOverride = nil
        }

        if userDefaults.object(forKey: hasCompletedBaseLevelOnboardingKey) != nil {
            self.hasCompletedBaseLevelOnboarding = userDefaults.bool(forKey: hasCompletedBaseLevelOnboardingKey)
        } else {
            self.hasCompletedBaseLevelOnboarding = hadPreviousLaunch
            if hadPreviousLaunch {
                userDefaults.set(true, forKey: hasCompletedBaseLevelOnboardingKey)
            }
        }

        self.appleHealthAutoImportEnabled = userDefaults.bool(forKey: appleHealthAutoImportEnabledKey)
        self.appleHealthAutoImportActivatedAt = userDefaults.object(forKey: appleHealthAutoImportActivatedAtKey) as? Date

    }
    
    private func saveMeasurementSystem() {
        userDefaults.set(measurementSystem.rawValue, forKey: measurementSystemKey)
        userDefaults.synchronize()
    }
    
    private func saveStepHeight() {
        userDefaults.set(stepHeight, forKey: stepHeightKey)
        userDefaults.synchronize()
    }
    
    private func saveFitnessLevel() {
        userDefaults.set(fitnessLevel.rawValue, forKey: fitnessLevelKey)
        userDefaults.synchronize()
    }

    private func saveSeededBaseLevel() {
        userDefaults.set(seededBaseLevel, forKey: seededBaseLevelKey)
        userDefaults.synchronize()
    }

    private func saveAutoCalculatedBaseLevel() {
        if let autoCalculatedBaseLevel {
            userDefaults.set(autoCalculatedBaseLevel, forKey: autoCalculatedBaseLevelKey)
        } else {
            userDefaults.removeObject(forKey: autoCalculatedBaseLevelKey)
        }
        userDefaults.synchronize()
    }

    private func saveManualBaseLevelOverride() {
        if let manualBaseLevelOverride {
            userDefaults.set(manualBaseLevelOverride, forKey: manualBaseLevelOverrideKey)
        } else {
            userDefaults.removeObject(forKey: manualBaseLevelOverrideKey)
        }
        userDefaults.synchronize()
    }

    private func saveHasCompletedBaseLevelOnboarding() {
        userDefaults.set(hasCompletedBaseLevelOnboarding, forKey: hasCompletedBaseLevelOnboardingKey)
        userDefaults.synchronize()
    }

    private func saveAppleHealthAutoImportEnabled() {
        userDefaults.set(appleHealthAutoImportEnabled, forKey: appleHealthAutoImportEnabledKey)
        userDefaults.synchronize()
    }

    private func saveAppleHealthAutoImportActivatedAt() {
        userDefaults.set(appleHealthAutoImportActivatedAt, forKey: appleHealthAutoImportActivatedAtKey)
        userDefaults.synchronize()
    }

    private func convertStepHeight(from oldSystem: MeasurementSystem, to newSystem: MeasurementSystem) {
        guard oldSystem != newSystem else { return }
        
        // Convert current step height to the new measurement system
        switch (oldSystem, newSystem) {
        case (.imperial, .metric):
            // Convert inches to centimeters
            stepHeight = stepHeight * 2.54
        case (.metric, .imperial):
            // Convert centimeters to inches
            stepHeight = stepHeight / 2.54
        default:
            break
        }
    }
    
    func setMeasurementSystem(_ system: MeasurementSystem) {
        withAnimation(.easeInOut(duration: 0.3)) {
            measurementSystem = system
        }
    }

    func setAppleHealthAutoImportEnabled(_ enabled: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            appleHealthAutoImportEnabled = enabled
        }
    }

    func hasDismissedAppleHealthAutoImportPrompt(for userID: String) -> Bool {
        Set(userDefaults.stringArray(forKey: appleHealthAutoImportPromptDismissedUserIDsKey) ?? [])
            .contains(userID)
    }

    func markAppleHealthAutoImportPromptDismissed(for userID: String) {
        var dismissedUserIDs = Set(userDefaults.stringArray(forKey: appleHealthAutoImportPromptDismissedUserIDsKey) ?? [])
        let inserted = dismissedUserIDs.insert(userID).inserted
        guard inserted else { return }

        userDefaults.set(Array(dismissedUserIDs).sorted(), forKey: appleHealthAutoImportPromptDismissedUserIDsKey)
        userDefaults.synchronize()
    }

    /// Resets the process-wide mirror after account deletion without writing any value back into
    /// the persistent domain that deletion just cleared.
    func resetInMemoryAfterAccountDeletion() {
        isResettingAfterAccountDeletion = true
        defer { isResettingAfterAccountDeletion = false }

        measurementSystem = .imperial
        stepHeight = MeasurementSystem.imperial.defaultStepHeight
        fitnessLevel = .intermediate
        seededBaseLevel = 7
        autoCalculatedBaseLevel = nil
        manualBaseLevelOverride = nil
        hasCompletedBaseLevelOnboarding = false
        appleHealthAutoImportEnabled = false
        appleHealthAutoImportActivatedAt = nil
    }

    func setStepHeight(_ height: Double) {
        stepHeight = height
    }
    
    func setFitnessLevel(_ level: FitnessLevel) {
        withAnimation(.easeInOut(duration: 0.3)) {
            fitnessLevel = level
        }
    }

    func completeBaseLevelOnboarding(with level: Int) {
        seededBaseLevel = SPMMappingService.clampedLevel(level)
        hasCompletedBaseLevelOnboarding = true
    }

    func saveBaseLevelSelection(_ level: Int) {
        let clampedLevel = SPMMappingService.clampedLevel(level)

        if autoCalculatedBaseLevel == nil {
            seededBaseLevel = clampedLevel
        } else if autoCalculatedBaseLevel == clampedLevel {
            manualBaseLevelOverride = nil
        } else {
            manualBaseLevelOverride = clampedLevel
        }

        hasCompletedBaseLevelOnboarding = true
    }

    func resetBaseLevelOverride() {
        manualBaseLevelOverride = nil
    }

    func updateAutoCalculatedBaseLevel(_ level: Int?) {
        autoCalculatedBaseLevel = level.map(SPMMappingService.clampedLevel)
    }

    func resolveBaseLevelBootstrap(hasWorkoutHistory: Bool) {
        if hasWorkoutHistory {
            hasCompletedBaseLevelOnboarding = true
        }
    }

    private static func migratedBaseLevel(for fitnessLevel: FitnessLevel) -> Int {
        switch fitnessLevel {
        case .beginner:
            return 5
        case .intermediate:
            return 8
        case .advanced:
            return 12
        }
    }
}
