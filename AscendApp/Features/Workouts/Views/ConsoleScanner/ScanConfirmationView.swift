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
    @FocusState private var isTextFieldFocused: Bool

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

    // Track discarded fields
    @State private var stepsDiscarded = false
    @State private var floorsDiscarded = false
    @State private var durationDiscarded = false
    @State private var caloriesDiscarded = false
    @State private var heartRateDiscarded = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var hasAnyDetectedValues: Bool {
        (result.stepsClimbed != nil && !stepsDiscarded) ||
        (result.floorsClimbed != nil && !floorsDiscarded) ||
        (result.elapsedTimeSeconds != nil && !durationDiscarded) ||
        (result.calories != nil && !caloriesDiscarded) ||
        (result.heartRateBpm != nil && !heartRateDiscarded)
    }

    private var notDetectedItems: [String] {
        var items: [String] = []
        if result.stepsClimbed == nil || stepsDiscarded { items.append("Steps") }
        if result.floorsClimbed == nil || floorsDiscarded { items.append("Floors") }
        if result.elapsedTimeSeconds == nil || durationDiscarded { items.append("Duration") }
        if result.calories == nil || caloriesDiscarded { items.append("Calories") }
        if result.heartRateBpm == nil || heartRateDiscarded { items.append("Heart Rate") }
        return items
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Scanned image thumbnail
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 250)
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

                // Extracted values (only show detected ones)
                if hasAnyDetectedValues {
                    VStack(spacing: 16) {
                        Text("Extracted Values")
                            .font(.montserratBold(size: 18))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Steps (if detected and not discarded)
                        if result.stepsClimbed != nil && !stepsDiscarded {
                            MetricRow(
                                label: "Steps",
                                value: $stepsValue,
                                icon: "figure.stairs",
                                effectiveColorScheme: effectiveColorScheme,
                                isFocused: $isTextFieldFocused,
                                onDiscard: { stepsDiscarded = true }
                            )
                        }

                        // Floors (if detected and not discarded)
                        if result.floorsClimbed != nil && !floorsDiscarded {
                            MetricRow(
                                label: "Floors",
                                value: $floorsValue,
                                icon: "building.2",
                                effectiveColorScheme: effectiveColorScheme,
                                isFocused: $isTextFieldFocused,
                                onDiscard: { floorsDiscarded = true }
                            )
                        }

                        // Duration (if detected and not discarded)
                        if result.elapsedTimeSeconds != nil && !durationDiscarded {
                            MetricRow(
                                label: "Duration",
                                value: $durationValue,
                                icon: "clock",
                                effectiveColorScheme: effectiveColorScheme,
                                isTime: true,
                                isFocused: $isTextFieldFocused,
                                onDiscard: { durationDiscarded = true }
                            )
                        }

                        // Calories (if detected and not discarded)
                        if result.calories != nil && !caloriesDiscarded {
                            MetricRow(
                                label: "Calories",
                                value: $caloriesValue,
                                icon: "flame",
                                effectiveColorScheme: effectiveColorScheme,
                                isFocused: $isTextFieldFocused,
                                onDiscard: { caloriesDiscarded = true }
                            )
                        }

                        // Heart Rate (if detected and not discarded)
                        if result.heartRateBpm != nil && !heartRateDiscarded {
                            MetricRow(
                                label: "Heart Rate",
                                value: $heartRateValue,
                                icon: "heart",
                                effectiveColorScheme: effectiveColorScheme,
                                isFocused: $isTextFieldFocused,
                                onDiscard: { heartRateDiscarded = true }
                            )
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                    )
                }

                // Not detected values
                if !notDetectedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Not Detected")
                            .font(.montserratBold(size: 18))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(notDetectedItems.joined(separator: ", "))
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.7))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.1) : .gray.opacity(0.03))
                    )
                }

                // Action buttons
                HStack(spacing: 12) {
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
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isTextFieldFocused = false
                }
                .font(.montserratSemiBold(size: 16))
            }
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
        // Parse edited values from text fields, respecting discarded fields
        let steps = stepsDiscarded ? nil : Int(stepsValue)
        let floors = floorsDiscarded ? nil : Double(floorsValue)
        let duration = durationDiscarded ? nil : parseDuration(durationValue)
        let cals = caloriesDiscarded ? nil : Double(caloriesValue)
        let hr = heartRateDiscarded ? nil : Int(heartRateValue)

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
    let icon: String
    let effectiveColorScheme: ColorScheme
    var isTime: Bool = false
    var isFocused: FocusState<Bool>.Binding
    var onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.accent)
                .frame(width: 32)

            Text(label)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .frame(width: 60, alignment: .leading)

            TextField("", text: $value)
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                .keyboardType(isTime ? .numbersAndPunctuation : .numberPad)
                .multilineTextAlignment(.trailing)
                .focused(isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.2) : .gray.opacity(0.3), lineWidth: 1)
                )

            // Discard button
            Button {
                onDiscard()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray.opacity(0.5))
            }
        }
    }
}
