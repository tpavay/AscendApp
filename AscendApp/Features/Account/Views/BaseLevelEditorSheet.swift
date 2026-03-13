import SwiftUI

struct BaseLevelEditorSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settingsManager = SettingsManager.shared
    @State private var selectedLevel: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init() {
        _selectedLevel = State(initialValue: SettingsManager.shared.effectiveBaseLevel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Base Level")
                        .font(.montserratBold(size: 28))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)

                    Text("The stairmaster level you can sustain for about 10 minutes at a steady effort. This personalizes your routine templates.")
                        .font(.montserratRegular(size: 16))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    Text("\(selectedLevel)")
                        .font(.montserratBold(size: 68))
                        .foregroundStyle(levelColor)

                    Text("\(SPMMappingService.spm(forLevel: selectedLevel)) SPM")
                        .font(.montserratMedium(size: 18))
                        .foregroundStyle(.secondary)

                    Text(IntensityTier.from(level: selectedLevel).displayName)
                        .font(.montserratSemiBold(size: 18))
                        .foregroundStyle(levelColor)
                }

                BaseLevelSlider(selectedLevel: $selectedLevel)

                stateDescription
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    } else {
                        Text("Save")
                            .font(.montserratBold(size: 20))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.accent)
                )
                .disabled(isSaving)

                Button("Cancel") {
                    dismiss()
                }
                .font(.montserratMedium(size: 18))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .appSheetBackground()
    }

    private var levelColor: Color {
        Color.heatMapColor(
            for: IntensityTier.from(level: selectedLevel).heatMapScore,
            colorScheme: colorScheme
        )
    }

    @ViewBuilder
    private var stateDescription: some View {
        switch settingsManager.baseLevelState {
        case .seeded:
            Text("Start here and it'll auto-adjust as you log workouts.")
                .font(.montserratRegular(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .autoCalculated:
            Text("Auto-calculated from your workouts. Adjust if needed.")
                .font(.montserratRegular(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .manualOverride:
            if let autoCalculatedBaseLevel = settingsManager.autoCalculatedBaseLevel {
                Button {
                    selectedLevel = autoCalculatedBaseLevel
                    HapticsManager.shared.trigger(.lightImpact)
                } label: {
                    (
                        Text("Auto-calculated level is \(autoCalculatedBaseLevel) from your workouts.")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(.secondary)
                        +
                        Text(" Reset")
                            .font(.montserratSemiBold(size: 16))
                            .foregroundStyle(.accent)
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        do {
            settingsManager.saveBaseLevelSelection(selectedLevel)
            try WorkoutDerivedDataService.recalculateAll(
                modelContext: modelContext,
                settingsManager: settingsManager
            )
            dismiss()
        } catch {
            errorMessage = error.userFriendlyMessage
        }

        isSaving = false
    }
}
