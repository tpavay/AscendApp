//
//  BestEffortsListView.swift
//  AscendApp
//
//  Created by GPT-5.1 on 11/20/25.
//

import SwiftUI
import SwiftData

/// Time period for filtering best efforts
enum BestEffortsTimePeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case allTime = "All Time"
    
    var id: String { rawValue }
    
    /// Returns the start date for this time period
    func startDate(from referenceDate: Date = Date()) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: referenceDate)
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: referenceDate)
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: referenceDate)
        case .allTime:
            return nil
        }
    }
}

struct BestEffortsListView: View {
    let workouts: [Workout]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var selectedTimePeriod: BestEffortsTimePeriod = .allTime

    // Weight records state
    @State private var weightRecordsSections: [WeightRecordsSection] = []
    @State private var aggregateEfforts: [AggregateWeightBestEffort] = []

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    /// Filter workouts based on selected time period
    private var filteredWorkouts: [Workout] {
        guard let startDate = selectedTimePeriod.startDate() else {
            return workouts // All time - no filtering
        }
        return workouts.filter { $0.date >= startDate }
    }

    private var efforts: [BestEffort] {
        BestEffortsBuilder.bestEfforts(from: filteredWorkouts)
    }

    private var hasWeightRecords: Bool {
        !weightRecordsSections.isEmpty || !aggregateEfforts.isEmpty
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Time Period Picker
                timePeriodPicker
                
                if efforts.isEmpty && !hasWeightRecords {
                    emptyState
                } else {
                    if !efforts.isEmpty {
                        effortsList
                    }

                    // Weight Records Section (only show for all-time)
                    if hasWeightRecords && selectedTimePeriod == .allTime {
                        weightRecordsSection
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationTitle("Best Efforts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: BestEffortsProgressView(workouts: filteredWorkouts)) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.accent)
                }
            }
        }
        .onAppear {
            loadWeightRecords()
        }
    }
    
    private var timePeriodPicker: some View {
        HStack(spacing: 8) {
            ForEach(BestEffortsTimePeriod.allCases) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimePeriod = period
                    }
                    HapticsManager.shared.trigger(.selection)
                } label: {
                    Text(period.rawValue)
                        .font(.montserratMedium(size: 13))
                        .foregroundStyle(
                            selectedTimePeriod == period
                                ? .white
                                : (effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTimePeriod == period ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
    }
    
    private var effortsList: some View {
        VStack(spacing: 12) {
            ForEach(efforts) { effort in
                NavigationLink(destination: WorkoutDetailView(workout: effort.workout)) {
                    BestEffortCard(effort: effort, colorScheme: effectiveColorScheme)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(emptyStateTitle)
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

            Text(emptyStateMessage)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
    
    private var emptyStateTitle: String {
        switch selectedTimePeriod {
        case .week:
            return "No Workouts This Week"
        case .month:
            return "No Workouts This Month"
        case .year:
            return "No Workouts This Year"
        case .allTime:
            return "No Best Efforts Yet"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedTimePeriod {
        case .week:
            return "Log a workout this week to see your best efforts."
        case .month:
            return "Log a workout this month to see your best efforts."
        case .year:
            return "Log a workout this year to see your best efforts."
        case .allTime:
            return "Start logging workouts to see your all‑time best sessions for steps, duration, heart rate, and more."
        }
    }

    // MARK: - Weight Records Section

    // Only show "Most Total Weight" as a standalone card
    private var mostTotalWeightEffort: AggregateWeightBestEffort? {
        aggregateEfforts.first { $0.recordType == .mostTotalWeight }
    }

    private var weightRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Only show "Most Total Weight" as a standalone card
            if let totalWeightEffort = mostTotalWeightEffort {
                NavigationLink(destination: WorkoutDetailView(workout: totalWeightEffort.workout)) {
                    AggregateWeightEffortCard(effort: totalWeightEffort, colorScheme: effectiveColorScheme)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Per-combo records grouped by equipment type
            ForEach(weightRecordsSections) { section in
                WeightEquipmentSection(
                    section: section,
                    colorScheme: effectiveColorScheme,
                    measurementSystem: settingsManager.measurementSystem
                )
            }
        }
    }

    // MARK: - Load Weight Records

    private func loadWeightRecords() {
        do {
            let weightRecords = try WeightPersonalRecordService.fetchCurrentWeightPersonalRecords(modelContext: modelContext)
            let aggregateRecords = try WeightPersonalRecordService.fetchCurrentAggregateRecords(modelContext: modelContext)

            weightRecordsSections = WeightBestEffortsBuilder.buildWeightRecordsSections(
                from: weightRecords,
                workouts: workouts,
                measurementSystem: settingsManager.measurementSystem
            )

            aggregateEfforts = WeightBestEffortsBuilder.buildAggregateEfforts(
                from: aggregateRecords,
                workouts: workouts,
                measurementSystem: settingsManager.measurementSystem
            )
        } catch {
            print("Error loading weight records: \(error)")
        }
    }
}

// MARK: - Weight Equipment Section (Compact Horizontal Layout)

private struct WeightEquipmentSection: View {
    let section: WeightRecordsSection
    let colorScheme: ColorScheme
    let measurementSystem: MeasurementSystem

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Equipment type header with chevron
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(section.equipmentType.displayName)
                        .font(.montserratSemiBold(size: 16))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Weight combo rows
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(section.weightCombos) { combo in
                        WeightComboRow(
                            combo: combo,
                            colorScheme: colorScheme,
                            measurementSystem: measurementSystem
                        )

                        if combo.id != section.weightCombos.last?.id {
                            Divider()
                                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.2))
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                )
                .padding(.top, 8)
            }
        }
        .padding(.top, 12)
    }
}

private struct WeightComboRow: View {
    let combo: WeightComboSection
    let colorScheme: ColorScheme
    let measurementSystem: MeasurementSystem

    // Get record value by type
    private func recordValue(for type: WeightRecordType) -> String {
        combo.records.first { $0.recordType == type }?.valueText ?? "--"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Weight combo label (e.g., "20 lbs Vest")
            Text(combo.displayName)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            // Metrics row - all 4 metrics horizontally
            HStack(spacing: 0) {
                MetricCell(
                    label: "Longest Duration",
                    value: recordValue(for: .longestDuration),
                    colorScheme: colorScheme
                )

                MetricCell(
                    label: "Most Steps",
                    value: recordValue(for: .mostSteps),
                    colorScheme: colorScheme
                )

                MetricCell(
                    label: "Most Floors",
                    value: recordValue(for: .mostFloors),
                    colorScheme: colorScheme
                )

                MetricCell(
                    label: "Highest SPM",
                    value: recordValue(for: .bestPace),
                    colorScheme: colorScheme,
                    isLast: true
                )
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

private struct MetricCell: View {
    let label: String
    let value: String
    let colorScheme: ColorScheme
    var isLast: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.montserratRegular(size: 10))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
                .lineLimit(1)

            Text(value)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AggregateWeightEffortCard: View {
    let effort: AggregateWeightBestEffort
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 16) {
            // Use system icon for most total weight, custom icon for equipment types
            if effort.recordType == .mostTotalWeight {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.accent)
                    .frame(width: 32)
            } else {
                Image(effort.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.accent)
                    .frame(width: 32)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(effort.title)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)

                Text(effort.detailText)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .lineLimit(2)
            }

            Spacer()

            Text(effort.valueText)
                .font(.montserratBold(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colorScheme == .dark ? .white.opacity(0.08) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

private struct BestEffortCard: View {
    let effort: BestEffort
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: effort.iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.accent)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(effort.title)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)
                
                Text(effort.detailText)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Text(effort.valueText)
                .font(.montserratBold(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colorScheme == .dark ? .white.opacity(0.08) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    let sampleWorkouts = [
        Workout(
            name: "Morning Climb",
            date: Date(),
            duration: 45 * 60,
            steps: 5200,
            floors: 40,
            stepsPerFloor: 16,
            avgHeartRate: 135,
            maxHeartRate: 168,
            caloriesBurned: 520,
            effortRating: 4.5,
            averageMETs: 7.2
        ),
        Workout(
            name: "Evening Session",
            date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            duration: 30 * 60,
            steps: 4300,
            floors: 32,
            stepsPerFloor: 16,
            avgHeartRate: 128,
            maxHeartRate: 160,
            caloriesBurned: 430,
            effortRating: 3.8,
            averageMETs: 6.5
        )
    ]
    
    NavigationStack {
        BestEffortsListView(workouts: sampleWorkouts)
    }
}

