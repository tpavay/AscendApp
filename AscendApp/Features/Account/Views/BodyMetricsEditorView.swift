import SwiftUI

struct BodyMetricsEditorView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var settingsManager = SettingsManager.shared
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var weightValue = 185
    @State private var heightFeet = 5
    @State private var heightInches = 10
    @State private var heightCentimeters = 178
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight
        case heightFeet
        case heightInches
        case heightCentimeters
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    ProgressView()
                        .tint(.accent)
                        .padding(.top, 40)
                } else {
                    metricsSection
                    saveButton
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .themedBackground()
        .navigationTitle("Body Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .keyboardAccessoryToolbar {
            Spacer(minLength: 0)

            Button {
                focusedField = nil
            } label: {
                KeyboardDoneAccessoryLabel()
            }
            .buttonStyle(.plain)
        }
        .task {
            await loadCurrentMetrics()
        }
        .alert("Profile update failed", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
        .trackOnce(screen: .bodyMetricsEditor)
    }

    private var metricsSection: some View {
        ProfileSection(title: "Body Metrics") {
            ProfileCardSurface {
                VStack(spacing: 0) {
                    metricRow(
                        title: "Body Weight",
                        content: weightInput
                    )

                    ProfileCardDivider()

                    metricRow(
                        title: "Height",
                        content: heightInput
                    )
                }
            }
        }
    }

    private var weightInput: some View {
        HStack(spacing: 8) {
            TextField("0", value: $weightValue, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .weight)
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 88)

            Text(settingsManager.measurementSystem.weightAbbreviation)
                .font(.montserratSemiBold(size: 14))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    @ViewBuilder
    private var heightInput: some View {
        switch settingsManager.measurementSystem {
        case .imperial:
            HStack(spacing: 8) {
                numericField(value: $heightFeet, field: .heightFeet, width: 44)
                Text("ft")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.58))

                numericField(value: $heightInches, field: .heightInches, width: 44)
                Text("in")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.58))
            }
        case .metric:
            HStack(spacing: 8) {
                numericField(value: $heightCentimeters, field: .heightCentimeters, width: 88)
                Text("cm")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                await saveMetrics()
            }
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("Save")
                        .font(.montserratBold(size: 14))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Capsule().fill(Color.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .opacity(isSaving ? 0.7 : 1)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    errorMessage = nil
                }
            }
        )
    }

    private func metricRow<Content: View>(
        title: String,
        content: Content
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func numericField(
        value: Binding<Int>,
        field: Field,
        width: CGFloat
    ) -> some View {
        TextField("0", value: value, format: .number)
            .keyboardType(.numberPad)
            .textFieldStyle(.plain)
            .focused($focusedField, equals: field)
            .font(.montserratBold(size: 20))
            .foregroundStyle(.white)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: width)
    }

    private func loadCurrentMetrics() async {
        defer { isLoading = false }

        guard let userID = authVM.user?.uid else {
            errorMessage = "User not authenticated"
            return
        }

        do {
            let userData = try await UserDataRepository.shared.getUserFromFirestore(userId: userID)
            applyMetrics(
                weightKg: userData.weightKg ?? 84,
                heightCm: userData.heightCm ?? 178
            )
        } catch {
            errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
    }

    private func applyMetrics(weightKg: Double, heightCm: Double) {
        switch settingsManager.measurementSystem {
        case .imperial:
            weightValue = Int(MeasurementSystem.metric.convertWeight(weightKg, to: .imperial).rounded())
            let totalInches = max(Int(MeasurementSystem.metric.convertHeight(heightCm, to: .imperial).rounded()), 0)
            heightFeet = totalInches / 12
            heightInches = totalInches % 12
        case .metric:
            weightValue = Int(weightKg.rounded())
            heightCentimeters = Int(heightCm.rounded())
        }
    }

    private func saveMetrics() async {
        guard isSaving == false else { return }
        focusedField = nil

        guard let metrics = normalizedMetrics() else { return }

        isSaving = true
        errorMessage = await authVM.scopedProfileUpdate(
            fallback: "Failed to update profile."
        ) {
            await authVM.updateOnboardingBodyMetrics(
                weightKg: metrics.weightKg,
                heightCm: metrics.heightCm
            )
        }
        isSaving = false

        if errorMessage == nil {
            dismiss()
        }
    }

    private func normalizedMetrics() -> (weightKg: Double, heightCm: Double)? {
        let weightKg: Double
        let heightCm: Double

        switch settingsManager.measurementSystem {
        case .imperial:
            let totalInches = (heightFeet * 12) + heightInches
            weightKg = MeasurementSystem.imperial.convertWeight(Double(weightValue), to: .metric)
            heightCm = MeasurementSystem.imperial.convertHeight(Double(totalInches), to: .metric)
        case .metric:
            weightKg = Double(weightValue)
            heightCm = Double(heightCentimeters)
        }

        guard weightKg > 0, weightKg <= 400 else {
            errorMessage = "Enter a valid body weight."
            return nil
        }

        guard heightCm >= 90, heightCm <= 240 else {
            errorMessage = "Enter a valid height."
            return nil
        }

        return (weightKg, heightCm)
    }
}

#Preview {
    NavigationStack {
        BodyMetricsEditorView()
            .environment(AuthenticationViewModel())
    }
}
