//
//  HeatMapMetric.swift
//  AscendApp
//
//  Heat map metric selection and scoring for the Progress calendar
//

import Foundation
import SwiftUI

/// Metrics available for heat map visualization
enum HeatMapMetric: String, CaseIterable, Identifiable {
    case effortScore = "effort_score"
    case primaryMetric = "primary_metric"
    case duration = "duration"
    case stepsPerMinute = "steps_per_minute"
    case calories = "calories"
    case avgHeartRate = "avg_heart_rate"
    case maxHeartRate = "max_heart_rate"
    case addedWeight = "added_weight"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .effortScore: return "Effort Score"
        case .primaryMetric: return "Steps"
        case .duration: return "Duration"
        case .stepsPerMinute: return "Steps/Min"
        case .calories: return "Calories"
        case .avgHeartRate: return "Avg HR"
        case .maxHeartRate: return "Max HR"
        case .addedWeight: return "Weight"
        }
    }

    var icon: String {
        switch self {
        case .effortScore: return "flame.fill"
        case .primaryMetric: return "figure.stair.stepper"
        case .duration: return "clock.fill"
        case .stepsPerMinute: return "speedometer"
        case .calories: return "bolt.fill"
        case .avgHeartRate: return "heart.fill"
        case .maxHeartRate: return "heart.fill"
        case .addedWeight: return "scalemass.fill"
        }
    }

    /// Whether this metric appears in the main stat cards
    var isInStatCards: Bool {
        switch self {
        case .effortScore, .primaryMetric, .duration, .stepsPerMinute, .calories:
            return true
        case .avgHeartRate, .maxHeartRate, .addedWeight:
            return false
        }
    }

    /// Metrics available in the "More" menu
    static var moreMetrics: [HeatMapMetric] {
        allCases.filter { !$0.isInStatCards }
    }

    /// Metrics shown in stat cards
    static var statCardMetrics: [HeatMapMetric] {
        allCases.filter { $0.isInStatCards }
    }
}

// MARK: - Heat Map Color Helper

extension Color {
    /// Returns a color for a given heat map score (0.0 to 1.0)
    /// Gradient: Gray (no data) -> Light Yellow -> Orange -> Deep Red
    static func heatMapColor(for score: Double, colorScheme: ColorScheme) -> Color {
        // Clamp score to valid range
        let s = min(1.0, max(0, score))

        // Color stops for smooth gradient
        // 0.0: Light yellow
        // 0.3: Yellow-orange
        // 0.6: Orange
        // 0.8: Red-orange
        // 1.0: Deep red

        if s < 0.3 {
            // Light yellow to yellow-orange
            let t = s / 0.3
            return Color(
                red: 1.0,
                green: 0.95 - (0.15 * t),
                blue: 0.7 - (0.4 * t)
            )
        } else if s < 0.6 {
            // Yellow-orange to orange
            let t = (s - 0.3) / 0.3
            return Color(
                red: 1.0,
                green: 0.8 - (0.25 * t),
                blue: 0.3 - (0.3 * t)
            )
        } else if s < 0.8 {
            // Orange to red-orange
            let t = (s - 0.6) / 0.2
            return Color(
                red: 1.0,
                green: 0.55 - (0.25 * t),
                blue: 0.0
            )
        } else {
            // Red-orange to deep red
            let t = (s - 0.8) / 0.2
            return Color(
                red: 1.0 - (0.1 * t),
                green: 0.3 - (0.3 * t),
                blue: 0.0
            )
        }
    }

    /// Returns a gradient for a given heat map score
    static func heatMapGradient(for score: Double, colorScheme: ColorScheme) -> LinearGradient {
        let baseColor = heatMapColor(for: score, colorScheme: colorScheme)
        let darkerColor = heatMapColor(for: min(1.0, score + 0.1), colorScheme: colorScheme)

        return LinearGradient(
            colors: [baseColor, darkerColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
