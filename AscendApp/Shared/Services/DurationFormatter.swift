//
//  DurationFormatter.swift
//  AscendApp
//
//  Created by Gemini CLI on 3/10/26.
//

import Foundation

/// Utility for formatting and parsing workout durations
struct DurationFormatter {
    /// Parses a right-aligned digit buffer into hours, minutes, and seconds.
    /// Example: `1234` becomes `00:12:34`.
    static func parse(rawDigits: String) -> (hours: Int, minutes: Int, seconds: Int) {
        let digits = String(rawDigits.filter(\.isNumber).prefix(6))
        guard !digits.isEmpty else { return (0, 0, 0) }

        var totalSeconds = 0

        for (index, digit) in digits.reversed().enumerated() {
            guard let digitValue = digit.wholeNumberValue else { continue }

            switch index {
            case 0:
                totalSeconds += digitValue
            case 1:
                totalSeconds += digitValue * 10
            case 2:
                totalSeconds += digitValue * 60
            case 3:
                totalSeconds += digitValue * 600
            case 4:
                totalSeconds += digitValue * 3600
            case 5:
                totalSeconds += digitValue * 36000
            default:
                break
            }
        }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return (hours, minutes, seconds)
    }
    
    /// Formats hours, minutes, and seconds into a string (H:MM:SS or MM:SS)
    static func format(hours: Int, minutes: Int, seconds: Int) -> String {
        let clampedHours = min(max(hours, 0), 999)
        let clampedMinutes = min(max(minutes, 0), 59)
        let clampedSeconds = min(max(seconds, 0), 59)
        
        if clampedHours > 0 {
            return "\(clampedHours):\(clampedMinutes < 10 ? "0" : "")\(clampedMinutes):\(clampedSeconds < 10 ? "0" : "")\(clampedSeconds)"
        } else {
            return "\(clampedMinutes < 10 ? "0" : "")\(clampedMinutes):\(clampedSeconds < 10 ? "0" : "")\(clampedSeconds)"
        }
    }
    
    /// Formats a TimeInterval into a string (H:MM:SS or MM:SS)
    static func format(duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        return format(hours: hours, minutes: minutes, seconds: seconds)
    }
}
