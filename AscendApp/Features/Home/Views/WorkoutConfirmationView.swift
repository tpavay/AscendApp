//
//  WorkoutConfirmationView.swift
//  AscendApp
//
//  Created by Claude on 2/19/26.
//

import SwiftUI

/// Confirmation view for reviewing parsed workout data before saving
struct WorkoutConfirmationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var themeManager = ThemeManager.shared
    @State private var editedData: ParsedWorkoutData
    
    let originalText: String
    let onConfirm: (ParsedWorkoutData) -> Void
    let onCancel: () -> Void
    
    init(
        parsedData: ParsedWorkoutData,
        originalText: String,
        onConfirm: @escaping (ParsedWorkoutData) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._editedData = State(initialValue: parsedData)
        self.originalText = originalText
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Original input
                    originalInputCard
                    
                    // Parsed data fields
                    parsedDataCard
                    
                    // Weight equipment
                    if let weights = editedData.weightEquipment, !weights.isEmpty {
                        weightEquipmentCard(weights)
                    }
                    
                    // Intervals
                    if let intervals = editedData.intervals, !intervals.isEmpty {
                        intervalsCard(intervals)
                    }
                    
                    // Notes
                    if editedData.notes != nil {
                        notesCard
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .scrollIndicators(.hidden)
            .themedBackground()
            .navigationTitle("Confirm Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(.accent)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HapticsManager.shared.trigger(.success)
                        onConfirm(editedData)
                    }
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(.accent)
                }
            }
        }
    }
    
    // MARK: - Original Input Card
    
    private var originalInputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What you said", systemImage: "quote.bubble")
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
            
            Text("\"\(originalText)\"")
                .font(.montserratRegular(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                .italic()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
        )
    }
    
    // MARK: - Parsed Data Card
    
    private var parsedDataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workout Details")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            // Duration
            EditableField(
                icon: "clock",
                label: "Duration",
                value: Binding(
                    get: { editedData.durationMinutes.map { "\($0)" } ?? "" },
                    set: { editedData.durationMinutes = Int($0) }
                ),
                unit: "minutes",
                colorScheme: effectiveColorScheme
            )
            
            // Steps
            EditableField(
                icon: "figure.stairs",
                label: "Steps",
                value: Binding(
                    get: { editedData.steps.map { "\($0)" } ?? "" },
                    set: { editedData.steps = Int($0) }
                ),
                unit: "steps",
                colorScheme: effectiveColorScheme
            )
            
            // Floors
            EditableField(
                icon: "building.2",
                label: "Floors",
                value: Binding(
                    get: { editedData.floors.map { "\($0)" } ?? "" },
                    set: { editedData.floors = Int($0) }
                ),
                unit: "floors",
                colorScheme: effectiveColorScheme
            )
            
            // Heart Rate
            if editedData.heartRateAvg != nil || editedData.heartRateMax != nil {
                HStack(spacing: 16) {
                    EditableField(
                        icon: "heart.fill",
                        label: "Avg HR",
                        value: Binding(
                            get: { editedData.heartRateAvg.map { "\($0)" } ?? "" },
                            set: { editedData.heartRateAvg = Int($0) }
                        ),
                        unit: "bpm",
                        colorScheme: effectiveColorScheme
                    )
                    
                    EditableField(
                        icon: "bolt.heart",
                        label: "Max HR",
                        value: Binding(
                            get: { editedData.heartRateMax.map { "\($0)" } ?? "" },
                            set: { editedData.heartRateMax = Int($0) }
                        ),
                        unit: "bpm",
                        colorScheme: effectiveColorScheme
                    )
                }
            }
            
            // Calories
            if editedData.calories != nil {
                EditableField(
                    icon: "flame.fill",
                    label: "Calories",
                    value: Binding(
                        get: { editedData.calories.map { "\($0)" } ?? "" },
                        set: { editedData.calories = Int($0) }
                    ),
                    unit: "kcal",
                    colorScheme: effectiveColorScheme
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }
    
    // MARK: - Weight Equipment Card
    
    private func weightEquipmentCard(_ weights: [ParsedWorkoutData.WeightEquipmentItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Weight Equipment", systemImage: "scalemass")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            ForEach(Array(weights.enumerated()), id: \.offset) { index, item in
                HStack {
                    Image(systemName: iconForWeightType(item.type))
                        .foregroundStyle(.accent)
                        .frame(width: 24)
                    
                    Text(item.type.capitalized.replacingOccurrences(of: "_", with: " "))
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    if let qty = item.quantity, qty > 1 {
                        Text("\(qty)x")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                    
                    Text("\(Int(item.weightLbs)) lbs")
                        .font(.montserratSemiBold(size: 15))
                        .foregroundStyle(.accent)
                }
                .padding(.vertical, 8)
                
                if index < weights.count - 1 {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }
    
    private func iconForWeightType(_ type: String) -> String {
        switch type.lowercased() {
        case "vest": return "tshirt"
        case "ankle_weights", "ankle weights": return "shoe"
        case "backpack": return "bag"
        case "dumbbells": return "dumbbell"
        default: return "scalemass"
        }
    }
    
    // MARK: - Intervals Card
    
    private func intervalsCard(_ intervals: [ParsedWorkoutData.IntervalItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Intervals", systemImage: "chart.bar")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            ForEach(Array(intervals.enumerated()), id: \.offset) { index, interval in
                HStack {
                    Text("Interval \(index + 1)")
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Spacer()
                    
                    if let duration = interval.durationMinutes {
                        Text("\(duration) min")
                            .font(.montserratSemiBold(size: 15))
                            .foregroundStyle(.accent)
                    }
                    
                    if let steps = interval.steps {
                        Text("• \(steps) steps")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }
    
    // MARK: - Notes Card
    
    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Text(editedData.notes ?? "")
                .font(.montserratRegular(size: 15))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }
}

// MARK: - Editable Field

private struct EditableField: View {
    let icon: String
    let label: String
    @Binding var value: String
    let unit: String
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .frame(width: 24)
            
            Text(label)
                .font(.montserratMedium(size: 15))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
            
            Spacer()
            
            HStack(spacing: 4) {
                TextField("--", text: $value)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                
                Text(unit)
                    .font(.montserratRegular(size: 14))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    WorkoutConfirmationView(
        parsedData: ParsedWorkoutData(
            durationMinutes: 30,
            steps: 3000,
            floors: 25,
            weightEquipment: [
                .init(type: "vest", weightLbs: 20, quantity: 1),
                .init(type: "ankle_weights", weightLbs: 2.5, quantity: 2)
            ],
            intervals: [
                .init(durationMinutes: 5, steps: nil),
                .init(durationMinutes: 10, steps: nil),
                .init(durationMinutes: 5, steps: nil)
            ],
            notes: "Felt great today!"
        ),
        originalText: "I did 30 minutes on the stairstepper with my 20 pound vest and ankle weights, 3000 steps total",
        onConfirm: { _ in },
        onCancel: { }
    )
}
