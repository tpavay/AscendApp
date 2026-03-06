import Foundation

struct OnboardingDraft: Codable, Equatable {
    var currentStep: OnboardingStepID
    var measurementSystem: MeasurementSystem
    var fitnessLevel: FitnessLevel
    var dateOfBirth: Date
    var gender: UserProfileGender
    var heightCm: Double
    var bodyWeightKg: Double
    var healthKitOptIn: Bool
    var notificationOptIn: Bool
    var locationSummary: UserLocationSummary

    static let defaultDateOfBirth = Calendar(identifier: .gregorian).date(from: DateComponents(year: 1995, month: 1, day: 1)) ?? .distantPast

    static var `default`: OnboardingDraft {
        let savedSystemRaw = UserDefaults.standard.string(forKey: "measurementSystem")
        let measurementSystem = MeasurementSystem(rawValue: savedSystemRaw ?? "") ?? .imperial

        return OnboardingDraft(
        currentStep: .welcome,
        measurementSystem: measurementSystem,
        fitnessLevel: .intermediate,
        dateOfBirth: defaultDateOfBirth,
        gender: .preferNotToSay,
        heightCm: 173,
        bodyWeightKg: 77,
        healthKitOptIn: false,
        notificationOptIn: false,
        locationSummary: .empty
    )
    }

    var isAuthReady: Bool {
        currentStep == .auth
    }

    mutating func goToNextStep() {
        guard let next = OnboardingStepID.allCases[safe: currentStep.index + 1] else {
            return
        }
        currentStep = next
    }

    mutating func goToPreviousStep() {
        guard let previous = OnboardingStepID.allCases[safe: currentStep.index - 1] else {
            return
        }
        currentStep = previous
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
