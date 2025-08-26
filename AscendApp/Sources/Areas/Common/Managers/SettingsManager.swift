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
    
    var preferredWorkoutMetric: WorkoutMetric {
        didSet {
            savePreferredMetric()
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
    }
    
    private func savePreferredMetric() {
        UserDefaults.standard.set(preferredWorkoutMetric.rawValue, forKey: preferredMetricKey)
        UserDefaults.standard.synchronize()
    }
    
    func setPreferredMetric(_ metric: WorkoutMetric) {
        withAnimation(.easeInOut(duration: 0.3)) {
            preferredWorkoutMetric = metric
        }
    }
}
