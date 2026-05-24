//
//  MeasurementSystem.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/26/25.
//

import Foundation

enum MeasurementSystem: String, CaseIterable, Codable, Identifiable {
    case imperial = "imperial"
    case metric = "metric"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .imperial: return "Imperial"
        case .metric: return "Metric"
        }
    }
    
    var description: String {
        switch self {
        case .imperial: return "Inches, feet, miles, pounds"
        case .metric: return "Centimeters, meters, kilometers, kilograms"
        }
    }
    
    // Step height units
    var stepHeightUnit: String {
        switch self {
        case .imperial: return "inches"
        case .metric: return "cm"
        }
    }
    
    var stepHeightAbbreviation: String {
        switch self {
        case .imperial: return "in"
        case .metric: return "cm"
        }
    }
    
    // Default step height values
    var defaultStepHeight: Double {
        switch self {
        case .imperial: return 8.0 // inches
        case .metric: return 20.3 // cm (8 inches converted)
        }
    }
    
    // Distance units for total climb
    var distanceUnit: String {
        switch self {
        case .imperial: return "feet"
        case .metric: return "meters"
        }
    }
    
    var distanceAbbreviation: String {
        switch self {
        case .imperial: return "ft"
        case .metric: return "m"
        }
    }
    
    // Conversion helpers
    func convertStepHeightToMeters(_ value: Double) -> Double {
        switch self {
        case .imperial:
            return value * 0.0254 // inches to meters
        case .metric:
            return value * 0.01 // cm to meters
        }
    }

    func convertMetersToDistanceUnit(_ meters: Double) -> Double {
        switch self {
        case .imperial:
            return meters * 3.28084 // meters to feet
        case .metric:
            return meters // already in meters
        }
    }

    // MARK: - Weight Units

    /// Full weight unit name (e.g., "pounds" or "kilograms")
    var weightUnit: String {
        switch self {
        case .imperial: return "pounds"
        case .metric: return "kilograms"
        }
    }

    /// Abbreviated weight unit (e.g., "lb" or "kg")
    var weightAbbreviation: String {
        switch self {
        case .imperial: return "lb"
        case .metric: return "kg"
        }
    }

    /// Convert weight from this system to the target system
    /// - Parameters:
    ///   - value: The weight value to convert
    ///   - target: The target measurement system
    /// - Returns: The converted weight value
    func convertWeight(_ value: Double, to target: MeasurementSystem) -> Double {
        if self == target { return value }
        switch (self, target) {
        case (.imperial, .metric):
            return value * 0.453592 // pounds to kilograms
        case (.metric, .imperial):
            return value / 0.453592 // kilograms to pounds
        default:
            return value
        }
    }

    /// Format a weight value with the appropriate unit abbreviation
    /// - Parameter value: The weight value
    /// - Returns: Formatted string (e.g., "20 lb" or "9.1 kg")
    func formatWeight(_ value: Double) -> String {
        let formatted = value.truncatingRemainder(dividingBy: 1) == 0
            ? value.formatted(.number.precision(.fractionLength(0)))
            : value.formatted(.number.precision(.fractionLength(1)))
        return "\(formatted) \(weightAbbreviation)"
    }
}
