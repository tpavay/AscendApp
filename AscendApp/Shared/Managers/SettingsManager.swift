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
    
    private let preferredMetricKey = "preferredWorkoutMetric"
    private let measurementSystemKey = "measurementSystem"
    private let stepHeightKey = "stepHeight"
    private let stepsPerFloorKey = "stepsPerFloor"
    private let fitnessLevelKey = "userFitnessLevel"
    private let seededBaseLevelKey = "seededBaseLevel"
    private let autoCalculatedBaseLevelKey = "autoCalculatedBaseLevel"
    private let manualBaseLevelOverrideKey = "manualBaseLevelOverride"
    private let hasCompletedBaseLevelOnboardingKey = "hasCompletedBaseLevelOnboarding"
    private let firstLaunchDateKey = "firstLaunchDate"
    private let appleHealthAutoImportEnabledKey = "appleHealthAutoImportEnabled"
    private let appleHealthAutoImportActivatedAtKey = "appleHealthAutoImportActivatedAt"
    private let appleHealthImportCoachMarkSeenUserIDsKey = "appleHealthImportCoachMarkSeenUserIDs"
    var preferredWorkoutMetric: WorkoutMetric {
        didSet {
            savePreferredMetric()
        }
    }
    
    var measurementSystem: MeasurementSystem {
        didSet {
            let oldSystem = oldValue
            saveMeasurementSystem()
            // Convert step height to new measurement system
            convertStepHeight(from: oldSystem, to: measurementSystem)
        }
    }
    
    var stepHeight: Double {
        didSet {
            saveStepHeight()
        }
    }
    
    var stepsPerFloor: Int {
        didSet {
            saveStepsPerFloor()
        }
    }

    var fitnessLevel: FitnessLevel {
        didSet {
            saveFitnessLevel()
        }
    }

    var seededBaseLevel: Int {
        didSet {
            saveSeededBaseLevel()
        }
    }

    var autoCalculatedBaseLevel: Int? {
        didSet {
            saveAutoCalculatedBaseLevel()
        }
    }

    var manualBaseLevelOverride: Int? {
        didSet {
            saveManualBaseLevelOverride()
        }
    }

    var hasCompletedBaseLevelOnboarding: Bool {
        didSet {
            saveHasCompletedBaseLevelOnboarding()
        }
    }

    var appleHealthAutoImportEnabled: Bool {
        didSet {
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

    private init() {
        // Load saved metric or default to steps
        if let savedMetric = UserDefaults.standard.string(forKey: preferredMetricKey),
           let metric = WorkoutMetric(rawValue: savedMetric) {
            self.preferredWorkoutMetric = metric
        } else {
            self.preferredWorkoutMetric = .steps
        }
        
        // Load saved measurement system or default to imperial
        let loadedMeasurementSystem: MeasurementSystem
        if let savedSystem = UserDefaults.standard.string(forKey: measurementSystemKey),
           let system = MeasurementSystem(rawValue: savedSystem) {
            loadedMeasurementSystem = system
        } else {
            loadedMeasurementSystem = .imperial
        }
        self.measurementSystem = loadedMeasurementSystem
        
        // Load saved step height or default based on measurement system
        if UserDefaults.standard.object(forKey: stepHeightKey) != nil {
            self.stepHeight = UserDefaults.standard.double(forKey: stepHeightKey)
        } else {
            self.stepHeight = loadedMeasurementSystem.defaultStepHeight
        }
        
        // Load saved steps per floor or default to 16
        self.stepsPerFloor = UserDefaults.standard.object(forKey: stepsPerFloorKey) != nil
            ? UserDefaults.standard.integer(forKey: stepsPerFloorKey)
            : 16

        // Load saved fitness level or default to intermediate
        let loadedFitnessLevel: FitnessLevel
        if let savedLevel = UserDefaults.standard.string(forKey: fitnessLevelKey),
           let level = FitnessLevel(rawValue: savedLevel) {
            loadedFitnessLevel = level
        } else {
            loadedFitnessLevel = .intermediate
        }
        self.fitnessLevel = loadedFitnessLevel

        let hadPreviousLaunch = UserDefaults.standard.object(forKey: firstLaunchDateKey) != nil
        let migratedSeededLevel = Self.migratedBaseLevel(for: loadedFitnessLevel)
        if let storedSeededBaseLevel = UserDefaults.standard.object(forKey: seededBaseLevelKey) as? Int {
            self.seededBaseLevel = SPMMappingService.clampedLevel(storedSeededBaseLevel)
        } else {
            let initialSeededBaseLevel = hadPreviousLaunch ? migratedSeededLevel : 7
            self.seededBaseLevel = initialSeededBaseLevel
            UserDefaults.standard.set(initialSeededBaseLevel, forKey: seededBaseLevelKey)
        }

        if let storedAutoCalculatedBaseLevel = UserDefaults.standard.object(forKey: autoCalculatedBaseLevelKey) as? Int {
            self.autoCalculatedBaseLevel = SPMMappingService.clampedLevel(storedAutoCalculatedBaseLevel)
        } else {
            self.autoCalculatedBaseLevel = nil
        }

        if let storedManualBaseLevelOverride = UserDefaults.standard.object(forKey: manualBaseLevelOverrideKey) as? Int {
            self.manualBaseLevelOverride = SPMMappingService.clampedLevel(storedManualBaseLevelOverride)
        } else {
            self.manualBaseLevelOverride = nil
        }

        if UserDefaults.standard.object(forKey: hasCompletedBaseLevelOnboardingKey) != nil {
            self.hasCompletedBaseLevelOnboarding = UserDefaults.standard.bool(forKey: hasCompletedBaseLevelOnboardingKey)
        } else {
            self.hasCompletedBaseLevelOnboarding = hadPreviousLaunch
            if hadPreviousLaunch {
                UserDefaults.standard.set(true, forKey: hasCompletedBaseLevelOnboardingKey)
            }
        }

        self.appleHealthAutoImportEnabled = UserDefaults.standard.bool(forKey: appleHealthAutoImportEnabledKey)
        self.appleHealthAutoImportActivatedAt = UserDefaults.standard.object(forKey: appleHealthAutoImportActivatedAtKey) as? Date

    }
    
    private func savePreferredMetric() {
        UserDefaults.standard.set(preferredWorkoutMetric.rawValue, forKey: preferredMetricKey)
        UserDefaults.standard.synchronize()
    }
    
    private func saveMeasurementSystem() {
        UserDefaults.standard.set(measurementSystem.rawValue, forKey: measurementSystemKey)
        UserDefaults.standard.synchronize()
    }
    
    private func saveStepHeight() {
        UserDefaults.standard.set(stepHeight, forKey: stepHeightKey)
        UserDefaults.standard.synchronize()
    }
    
    private func saveStepsPerFloor() {
        UserDefaults.standard.set(stepsPerFloor, forKey: stepsPerFloorKey)
        UserDefaults.standard.synchronize()
    }

    private func saveFitnessLevel() {
        UserDefaults.standard.set(fitnessLevel.rawValue, forKey: fitnessLevelKey)
        UserDefaults.standard.synchronize()
    }

    private func saveSeededBaseLevel() {
        UserDefaults.standard.set(seededBaseLevel, forKey: seededBaseLevelKey)
        UserDefaults.standard.synchronize()
    }

    private func saveAutoCalculatedBaseLevel() {
        if let autoCalculatedBaseLevel {
            UserDefaults.standard.set(autoCalculatedBaseLevel, forKey: autoCalculatedBaseLevelKey)
        } else {
            UserDefaults.standard.removeObject(forKey: autoCalculatedBaseLevelKey)
        }
        UserDefaults.standard.synchronize()
    }

    private func saveManualBaseLevelOverride() {
        if let manualBaseLevelOverride {
            UserDefaults.standard.set(manualBaseLevelOverride, forKey: manualBaseLevelOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: manualBaseLevelOverrideKey)
        }
        UserDefaults.standard.synchronize()
    }

    private func saveHasCompletedBaseLevelOnboarding() {
        UserDefaults.standard.set(hasCompletedBaseLevelOnboarding, forKey: hasCompletedBaseLevelOnboardingKey)
        UserDefaults.standard.synchronize()
    }

    private func saveAppleHealthAutoImportEnabled() {
        UserDefaults.standard.set(appleHealthAutoImportEnabled, forKey: appleHealthAutoImportEnabledKey)
        UserDefaults.standard.synchronize()
    }

    private func saveAppleHealthAutoImportActivatedAt() {
        UserDefaults.standard.set(appleHealthAutoImportActivatedAt, forKey: appleHealthAutoImportActivatedAtKey)
        UserDefaults.standard.synchronize()
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
    
    func setPreferredMetric(_ metric: WorkoutMetric) {
        withAnimation(.easeInOut(duration: 0.3)) {
            preferredWorkoutMetric = metric
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

    func hasSeenAppleHealthImportCoachMark(for userID: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: appleHealthImportCoachMarkSeenUserIDsKey) ?? [])
            .contains(userID)
    }

    func markAppleHealthImportCoachMarkSeen(for userID: String) {
        var seenUserIDs = Set(UserDefaults.standard.stringArray(forKey: appleHealthImportCoachMarkSeenUserIDsKey) ?? [])
        let inserted = seenUserIDs.insert(userID).inserted
        guard inserted else { return }

        UserDefaults.standard.set(Array(seenUserIDs).sorted(), forKey: appleHealthImportCoachMarkSeenUserIDsKey)
        UserDefaults.standard.synchronize()
    }

    func setStepHeight(_ height: Double) {
        stepHeight = height
    }
    
    func setStepsPerFloor(_ steps: Int) {
        stepsPerFloor = steps
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
