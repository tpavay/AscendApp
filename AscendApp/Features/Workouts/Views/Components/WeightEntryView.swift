//
//  WeightEntryView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/29/25.
//

import SwiftUI

/// Reusable component for entering/editing weight equipment configuration
struct WeightEntryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    @Binding var configuration: WeightConfiguration
    let measurementSystem: MeasurementSystem

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(WeightEquipmentType.allCases.enumerated()), id: \.element.id) { index, equipmentType in
                if index > 0 {
                    Divider()
                        .padding(.leading, 48)
                }

                WeightEquipmentRow(
                    equipmentType: equipmentType,
                    entry: binding(for: equipmentType),
                    measurementSystem: measurementSystem,
                    effectiveColorScheme: effectiveColorScheme
                )
            }
        }
        .background(sectionBackground)
    }

    private func binding(for type: WeightEquipmentType) -> Binding<WeightEntry> {
        Binding(
            get: {
                configuration.entry(for: type) ?? WeightEntry(
                    equipmentType: type,
                    weightValue: 0,
                    isEnabled: false
                )
            },
            set: { newEntry in
                if let index = configuration.entries.firstIndex(where: { $0.equipmentType == type }) {
                    configuration.entries[index] = newEntry
                } else {
                    configuration.entries.append(newEntry)
                }
            }
        )
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
    }
}

/// Individual row for a single equipment type
private struct WeightEquipmentRow: View {
    let equipmentType: WeightEquipmentType
    @Binding var entry: WeightEntry
    let measurementSystem: MeasurementSystem
    let effectiveColorScheme: ColorScheme

    @State private var weightText: String = ""
    @FocusState private var isWeightFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Header with toggle
            HStack(spacing: 12) {
                // Icon
                equipmentIcon
                    .frame(width: 24, height: 24)

                // Title and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(equipmentType.displayName)
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    if equipmentType.isPaired {
                        Text("Weight per item")
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    }
                }

                Spacer()

                Toggle("", isOn: $entry.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .accent))
                    .labelsHidden()
            }

            // Weight input (shown when enabled)
            if entry.isEnabled {
                HStack(spacing: 12) {
                    // Spacer to align with toggle row content
                    Color.clear
                        .frame(width: 24)

                    // Weight input field
                    HStack(spacing: 8) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.montserratMedium(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($isWeightFieldFocused)
                            .onChange(of: weightText) { _, newValue in
                                if let value = Double(newValue) {
                                    entry.weightValue = value
                                } else if newValue.isEmpty {
                                    entry.weightValue = 0
                                }
                            }

                        Text(measurementSystem.weightAbbreviation)
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(effectiveColorScheme == .dark ? .white.opacity(0.08) : .gray.opacity(0.1))
                    )

                    Spacer()

                    // Total weight display for paired items
                    if equipmentType.isPaired && entry.weightValue > 0 {
                        Text("(\(measurementSystem.formatWeight(entry.totalWeight)) total)")
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.2), value: entry.isEnabled)
        .onAppear {
            if entry.weightValue > 0 {
                weightText = formatWeightValue(entry.weightValue)
            }
        }
        .onChange(of: entry.isEnabled) { _, isEnabled in
            if isEnabled && entry.weightValue == 0 {
                // Focus the weight field when enabling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isWeightFieldFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private var equipmentIcon: some View {
        // Try custom icon first, fall back to SF Symbol
        if let _ = UIImage(named: equipmentType.iconName) {
            Image(equipmentType.iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            // Fallback SF Symbols
            Image(systemName: fallbackSFSymbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.accent)
        }
    }

    private var fallbackSFSymbol: String {
        switch equipmentType {
        case .weightedVest: return "tshirt.fill"
        case .dumbbells: return "dumbbell.fill"
        case .barbell: return "figure.strengthtraining.traditional"
        case .ankleWeights: return "shoe.fill"
        case .wristWeights: return "hand.raised.fill"
        }
    }

    private func formatWeightValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - Preview

#Preview("Weight Entry - Empty") {
    struct PreviewWrapper: View {
        @State private var config = WeightConfiguration.empty

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WEIGHTS USED (OPTIONAL)")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.gray)
                        .padding(.leading, 4)

                    WeightEntryView(
                        configuration: $config,
                        measurementSystem: .imperial
                    )
                }
                .padding(20)
            }
            .background(Color.jet)
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.dark)
}

#Preview("Weight Entry - With Data") {
    struct PreviewWrapper: View {
        @State private var config = WeightConfiguration(entries: [
            WeightEntry(equipmentType: .weightedVest, weightValue: 20, isEnabled: true),
            WeightEntry(equipmentType: .ankleWeights, weightValue: 5, isEnabled: true)
        ])

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WEIGHTS USED")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.gray)
                        .padding(.leading, 4)

                    WeightEntryView(
                        configuration: $config,
                        measurementSystem: .imperial
                    )

                    Text("Total: \(MeasurementSystem.imperial.formatWeight(config.totalWeight))")
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.jet)
        }
    }

    return PreviewWrapper()
        .preferredColorScheme(.dark)
}
