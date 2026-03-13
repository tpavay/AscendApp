import SwiftUI

struct BaseLevelOnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var settingsManager = SettingsManager.shared
    @State private var selectedLevel = SettingsManager.shared.seededBaseLevel
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("Your Base Level")
                    .font(.montserratBold(size: 32))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)

                Text("Set the stairmaster level you can sustain for about 10 minutes at a steady effort. This personalizes your routines from day one.")
                    .font(.montserratRegular(size: 16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                Text("\(selectedLevel)")
                    .font(.montserratBold(size: 84))
                    .foregroundStyle(levelColor)

                Text("\(SPMMappingService.spm(forLevel: selectedLevel)) SPM")
                    .font(.montserratMedium(size: 20))
                    .foregroundStyle(.secondary)

                Text(IntensityTier.from(level: selectedLevel).displayName)
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(levelColor)
            }

            BaseLevelSlider(selectedLevel: $selectedLevel)

            Text("Start here and it'll auto-adjust as you log workouts.")
                .font(.montserratRegular(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            if let errorMessage {
                Text(errorMessage)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            Button {
                completeOnboarding()
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                } else {
                    Text("Continue")
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
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .themedBackground()
        .interactiveDismissDisabled()
    }

    private var levelColor: Color {
        Color.heatMapColor(
            for: IntensityTier.from(level: selectedLevel).heatMapScore,
            colorScheme: colorScheme
        )
    }

    private func completeOnboarding() {
        isSaving = true
        errorMessage = nil

        do {
            settingsManager.completeBaseLevelOnboarding(with: selectedLevel)
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
