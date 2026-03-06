import Foundation
import Observation

@MainActor
@Observable
final class OnboardingStateManager {
    static let shared = OnboardingStateManager()

    private let completedKey = "onboardingV2Completed"
    private let currentStepKey = "onboardingV2CurrentStep"
    private let draftKey = "onboardingV2Draft"
    private let versionKey = "onboardingV2Version"
    private let oldFitnessOnboardingKey = "hasCompletedFitnessOnboarding"
    private let onboardingVersion = 2

    var draft: OnboardingDraft {
        didSet {
            persistDraft()
        }
    }
    var isCompleted: Bool

    private init() {
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: oldFitnessOnboardingKey) && !defaults.bool(forKey: completedKey) {
            defaults.set(true, forKey: completedKey)
            defaults.set(onboardingVersion, forKey: versionKey)
        }

        let savedVersion = defaults.integer(forKey: versionKey)
        if savedVersion == onboardingVersion,
           let data = defaults.data(forKey: draftKey),
           let decoded = try? JSONDecoder().decode(OnboardingDraft.self, from: data) {
            draft = decoded
        } else {
            draft = OnboardingDraft.default
        }

        isCompleted = defaults.bool(forKey: completedKey)

        if let rawStep = defaults.string(forKey: currentStepKey),
           let step = OnboardingStepID(rawValue: rawStep) {
            draft.currentStep = step
        }

        persistDraft()
    }

    var currentStep: OnboardingStepID {
        draft.currentStep
    }

    var canGoBack: Bool {
        currentStep.index > 0
    }

    func updateDraft(_ update: (inout OnboardingDraft) -> Void) {
        update(&draft)
    }

    func goToNextStep() {
        draft.goToNextStep()
    }

    func goToPreviousStep() {
        draft.goToPreviousStep()
    }

    func markCompleted() {
        isCompleted = true
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: completedKey)
        defaults.set(onboardingVersion, forKey: versionKey)
        defaults.set(OnboardingStepID.auth.rawValue, forKey: currentStepKey)
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: draftKey)
        }
        defaults.synchronize()
    }

    func resetForDebug() {
        draft = OnboardingDraft.default
        isCompleted = false

        let defaults = UserDefaults.standard
        defaults.set(false, forKey: completedKey)
        defaults.set(onboardingVersion, forKey: versionKey)
    }

    private func persistDraft() {
        let defaults = UserDefaults.standard
        defaults.set(draft.currentStep.rawValue, forKey: currentStepKey)

        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: draftKey)
        }

        defaults.set(onboardingVersion, forKey: versionKey)
        defaults.synchronize()
    }
}
