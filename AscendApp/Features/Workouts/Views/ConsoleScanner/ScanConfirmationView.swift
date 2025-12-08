//
//  ScanConfirmationView.swift
//  AscendApp
//
//  Created by Claude on 12/8/25.
//

import SwiftUI

/// View for reviewing extracted workout metrics before proceeding
struct ScanConfirmationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared

    let result: ConsoleScanResult
    let image: UIImage
    let onConfirm: (ConsoleScanResult) -> Void
    let onRescan: () -> Void

    // Editable values (in case user wants to adjust)
    @State private var stepsValue: String = ""
    @State private var floorsValue: String = ""
    @State private var durationValue: String = ""
    @State private var caloriesValue: String = ""
    @State private var heartRateValue: String = ""

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Scanned image thumbnail
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(effectiveColorScheme == .dark ? .white.opacity(0.2) : .gray.opacity(0.3), lineWidth: 1)
                    )

                // Status message
                if result.hasValidData {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Workout data extracted successfully")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("No workout data found in image")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }
                }

                // Extracted metrics
                VStack(spacing: 16) {
                    Text("Extracted Values")
                        .font(.montserratBold(size: 18))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Steps
                    MetricRow(
                        label: "Steps",
                        value: $stepsValue,
                        placeholder: "Not detected",
                        icon: "figure.stairs",
                        effectiveColorScheme: effectiveColorScheme
                    )

                    // Floors
                    MetricRow(
                        label: "Floors",
                        value: $floorsValue,
                        placeholder: "Not detected",
                        icon: "building.2",
                        effectiveColorScheme: effectiveColorScheme
                    )

                    // Duration
                    MetricRow(
                        label: "Duration",
                        value: $durationValue,
                        placeholder: "Not detected",
                        icon: "clock",
                        effectiveColorScheme: effectiveColorScheme,
                        isTime: true
                    )

                    // Calories (optional)
                    MetricRow(
                        label: "Calories",
                        value: $caloriesValue,
                        placeholder: "Not detected",
                        icon: "flame",
                        effectiveColorScheme: effectiveColorScheme
                    )

                    // Heart Rate (optional)
                    MetricRow(
                        label: "Heart Rate",
                        value: $heartRateValue,
                        placeholder: "Not detected",
                        icon: "heart",
                        effectiveColorScheme: effectiveColorScheme
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                )

                // Notes from AI (if any)
                if let notes = result.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.montserratSemiBold(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                        Text(notes)
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(effectiveColorScheme == .dark ? .blue.opacity(0.1) : .blue.opacity(0.05))
                    )
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        let updatedResult = buildUpdatedResult()
                        onConfirm(updatedResult)
                    } label: {
                        Text(result.hasValidData ? "Use Values" : "Use Anyway")
                            .font(.montserratSemiBold(size: 16))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onRescan()
                    } label: {
                        Text("Rescan")
                            .font(.montserratSemiBold(size: 16))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.1))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            populateFields()
        }
    }

    /// Populate editable fields from scan result
    private func populateFields() {
        if let steps = result.stepsClimbed {
            stepsValue = String(steps)
        }
        if let floors = result.floorsClimbed {
            floorsValue = String(Int(floors))
        }
        if let seconds = result.elapsedTimeSeconds {
            durationValue = formatDuration(seconds)
        }
        if let calories = result.calories {
            caloriesValue = String(Int(calories))
        }
        if let hr = result.heartRateBpm {
            heartRateValue = String(hr)
        }
    }

    /// Format seconds as MM:SS or H:MM:SS
    private func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Parse duration string back to seconds
    private func parseDuration(_ string: String) -> Int? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: // MM:SS
            return parts[0] * 60 + parts[1]
        case 3: // H:MM:SS
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }

    /// Build updated result from edited values
    private func buildUpdatedResult() -> ConsoleScanResult {
        // Parse edited values from text fields
        let steps = Int(stepsValue)
        let floors = Double(floorsValue)
        let duration = parseDuration(durationValue)
        let cals = Double(caloriesValue)
        let hr = Int(heartRateValue)

        return ConsoleScanResult(
            stepsClimbed: steps,
            floorsClimbed: floors,
            stepsPerMinute: result.stepsPerMinute,
            machineLevel: result.machineLevel,
            calories: cals,
            heartRateBpm: hr,
            elapsedTimeSeconds: duration,
            notes: result.notes
        )
    }
}

// MARK: - Metric Row

struct MetricRow: View {
    let label: String
    @Binding var value: String
    let placeholder: String
    let icon: String
    let effectiveColorScheme: ColorScheme
    var isTime: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.accent)
                .frame(width: 32)

            Text(label)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .frame(width: 80, alignment: .leading)

            TextField(placeholder, text: $value)
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .keyboardType(isTime ? .numbersAndPunctuation : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }
}
