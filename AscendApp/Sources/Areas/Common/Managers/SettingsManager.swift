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
    
    func setStepHeight(_ height: Double) {
        stepHeight = height
    }
    
    func setStepsPerFloor(_ steps: Int) {
        stepsPerFloor = steps
    }
}
