//
//  MeasurementSystem.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/26/25.
//

import Foundation

enum MeasurementSystem: String, CaseIterable, Identifiable {
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
    
    // Default steps per floor (same for both systems)
    var defaultStepsPerFloor: Int {
        return 16
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
}