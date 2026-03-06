import SwiftUI

struct OnboardingProfileSettingsView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss

    @State private var onboardingState = OnboardingStateManager.shared
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileSection(title: "Identity") {
                    ProfileCardSurface {
                        VStack(spacing: 0) {
                            profileDateRow
                            ProfileCardDivider()
                            profileGenderRow
                        }
                        .padding(16)
                    }
                }

                ProfileSection(title: "Body Metrics") {
                    ProfileCardSurface {
                        VStack(spacing: 16) {
                            profileHeightRow
                            profileBodyWeightRow
                        }
                        .padding(16)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.montserratRegular(size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
        .themedBackground()
        .navigationTitle("Body & Profile Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await saveChanges()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                            .font(.montserratSemiBold(size: 15))
                    }
                }
                .disabled(isSaving)
            }
        }
    }

    private var profileDateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date of Birth")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.secondary)

            DatePicker(
                "Date of Birth",
                selection: $onboardingState.draft.dateOfBirth,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var profileGenderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gender")
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(UserProfileGender.allCases) { option in
                    Button {
                        onboardingState.draft.gender = option
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .font(.montserratRegular(size: 15))
                                .foregroundStyle(.primary)

                            Spacer()

                            Image(systemName: onboardingState.draft.gender == option ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(onboardingState.draft.gender == option ? .accent : .secondary.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.secondary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var profileHeightRow: some View {
        profileMetricRow(
            title: "Height",
            unit: onboardingState.draft.measurementSystem == .metric ? "cm" : "in",
            value: displayedHeightBinding
        )
    }

    private var profileBodyWeightRow: some View {
        profileMetricRow(
            title: "Bodyweight",
            unit: onboardingState.draft.measurementSystem == .metric ? "kg" : "lb",
            value: displayedBodyWeightBinding
        )
    }

    private func profileMetricRow(title: String, unit: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(
                    title,
                    value: value,
                    format: .number.precision(.fractionLength(0...1))
                )
                .font(.montserratSemiBold(size: 18))
                .keyboardType(.decimalPad)

                Text(unit)
                    .font(.montserratRegular(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.secondary.opacity(0.08))
            )
        }
    }

    private var displayedHeightBinding: Binding<Double> {
        Binding {
            onboardingState.draft.measurementSystem == .metric
                ? onboardingState.draft.heightCm
                : onboardingState.draft.heightCm / 2.54
        } set: { newValue in
            let clamped = max(newValue, 1)
            onboardingState.draft.heightCm = onboardingState.draft.measurementSystem == .metric
                ? clamped
                : clamped * 2.54
        }
    }

    private var displayedBodyWeightBinding: Binding<Double> {
        Binding {
            onboardingState.draft.measurementSystem == .metric
                ? onboardingState.draft.bodyWeightKg
                : onboardingState.draft.bodyWeightKg / 0.453592
        } set: { newValue in
            let clamped = max(newValue, 1)
            onboardingState.draft.bodyWeightKg = onboardingState.draft.measurementSystem == .metric
                ? clamped
                : clamped * 0.453592
        }
    }

    private func saveChanges() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        guard let userId = authVM.user?.uid else {
            errorMessage = "You need to be signed in to save profile changes."
            isSaving = false
            return
        }

        do {
            try await UserDataRepository.shared.upsertOnboardingProfile(userId: userId, draft: onboardingState.draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    NavigationStack {
        OnboardingProfileSettingsView()
            .environment(AuthenticationViewModel())
    }
}
