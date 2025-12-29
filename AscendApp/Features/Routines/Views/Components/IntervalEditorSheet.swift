import SwiftUI

struct IntervalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared

    let interval: RoutineInterval?
    let onSave: (RoutineInterval) -> Void

    // Form state
    @State private var minutes: Int = 1
    @State private var seconds: Int = 0
    @State private var intensityType: IntensityType = .level
    @State private var intensityValue: Int = 8
    @State private var sidewaysDirection: SidewaysDirection? = nil
    @State private var skipStep: Bool = false
    @State private var backwardStep: Bool = false
    @State private var holdingBars: Bool = false

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var isValid: Bool {
        (minutes > 0 || seconds > 0) && intensityValue > 0
    }

    private var isEditing: Bool {
        interval != nil
    }

    init(interval: RoutineInterval? = nil, onSave: @escaping (RoutineInterval) -> Void) {
        self.interval = interval
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    durationSection
                    intensitySection
                    modifiersSection
                }
                .padding(20)
            }
            .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
            .navigationTitle(isEditing ? "Edit Interval" : "New Interval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.accent)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveInterval()
                    }
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(isValid ? .accent : .gray)
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            if let interval = interval {
                loadInterval(interval)
            }
        }
    }

    // MARK: - Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Duration")

            HStack(spacing: 16) {
                // Minutes
                VStack(spacing: 8) {
                    Text("Minutes")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

                    Picker("Minutes", selection: $minutes) {
                        ForEach(0..<60, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                    .clipped()
                }
                .frame(maxWidth: .infinity)

                // Seconds
                VStack(spacing: 8) {
                    Text("Seconds")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)

                    Picker("Seconds", selection: $seconds) {
                        ForEach(0..<60, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                    .clipped()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(sectionBackground)
        }
    }

    // MARK: - Intensity Section

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Intensity")

            VStack(spacing: 16) {
                // Type picker
                Picker("Intensity Type", selection: $intensityType) {
                    ForEach(IntensityType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                // Value
                VStack(spacing: 12) {
                    HStack {
                        Text(intensityType == .level ? "Level" : "Steps per Minute")
                            .font(.montserratRegular(size: 14))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

                        Spacer()

                        Text(intensityDisplayValue)
                            .font(.montserratSemiBold(size: 18))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }

                    if intensityType == .level {
                        Slider(value: Binding(
                            get: { Double(intensityValue) },
                            set: { intensityValue = Int($0) }
                        ), in: 1...20, step: 1)
                        .tint(.accent)
                    } else {
                        Slider(value: Binding(
                            get: { Double(intensityValue) },
                            set: { intensityValue = Int($0) }
                        ), in: 40...200, step: 5)
                        .tint(.accent)
                    }
                }
            }
            .padding(16)
            .background(sectionBackground)
        }
        .onChange(of: intensityType) { _, newType in
            // Reset to sensible default when switching types
            if newType == .level {
                intensityValue = min(max(intensityValue, 1), 20)
                if intensityValue > 20 {
                    intensityValue = 8
                }
            } else {
                if intensityValue < 40 {
                    intensityValue = 100
                }
            }
        }
    }

    private var intensityDisplayValue: String {
        if intensityType == .level {
            return "\(intensityValue)"
        } else {
            return "\(intensityValue) SPM"
        }
    }

    // MARK: - Modifiers Section

    private var modifiersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Modifiers (Optional)")

            VStack(spacing: 0) {
                sidewaysDirectionPicker

                Divider()
                    .padding(.leading, 48)

                modifierToggle(
                    title: "Skip Step",
                    subtitle: "Double-step every other stair",
                    icon: "arrow.up.to.line",
                    isOn: $skipStep
                )

                Divider()
                    .padding(.leading, 48)

                modifierToggle(
                    title: "Backward Step",
                    subtitle: "Face away from the console",
                    icon: "arrow.uturn.backward",
                    isOn: $backwardStep
                )

                Divider()
                    .padding(.leading, 48)

                modifierToggle(
                    title: "Holding Bars",
                    subtitle: "Hold the side bars for support",
                    icon: "hand.raised",
                    isOn: $holdingBars
                )
            }
            .background(sectionBackground)
        }
    }

    private var sidewaysDirectionPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sideways Climb")
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text("Step sideways on the machine")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                }

                Spacer()
            }

            Picker("Sideways Direction", selection: $sidewaysDirection) {
                Text("Off").tag(SidewaysDirection?.none)
                Text("Face Left").tag(SidewaysDirection?.some(.left))
                Text("Face Right").tag(SidewaysDirection?.some(.right))
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
    }

    private func modifierToggle(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.montserratMedium(size: 15))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                    Text(subtitle)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .accent))
        .padding(16)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.montserratMedium(size: 12))
            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
            .padding(.leading, 4)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .gray.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
            )
    }

    private func loadInterval(_ interval: RoutineInterval) {
        let totalSeconds = Int(interval.duration)
        minutes = totalSeconds / 60
        seconds = totalSeconds % 60
        intensityType = interval.intensityType
        intensityValue = interval.intensityValue
        sidewaysDirection = interval.modifiers.sidewaysDirection
        skipStep = interval.modifiers.skipStep
        backwardStep = interval.modifiers.backwardStep
        holdingBars = interval.modifiers.holdingBars
    }

    private func saveInterval() {
        let duration = TimeInterval(minutes * 60 + seconds)
        let modifiers = IntervalModifiers(
            sidewaysDirection: sidewaysDirection,
            skipStep: skipStep,
            backwardStep: backwardStep,
            holdingBars: holdingBars
        )

        let newInterval = RoutineInterval(
            id: interval?.id ?? UUID(),
            duration: duration,
            intensityType: intensityType,
            intensityValue: intensityValue,
            modifiers: modifiers,
            order: interval?.order ?? 0
        )

        onSave(newInterval)
        dismiss()
    }
}

#Preview("New Interval") {
    IntervalEditorSheet { interval in
        print("Saved interval: \(interval)")
    }
}

#Preview("Edit Interval") {
    let sampleInterval = RoutineInterval(
        duration: 180,
        intensityType: .level,
        intensityValue: 12,
        modifiers: IntervalModifiers(sidewaysDirection: .left),
        order: 0
    )

    IntervalEditorSheet(interval: sampleInterval) { interval in
        print("Updated interval: \(interval)")
    }
}

#Preview("Dark Mode") {
    IntervalEditorSheet { interval in
        print("Saved interval: \(interval)")
    }
    .preferredColorScheme(.dark)
}
