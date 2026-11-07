import SwiftUI

/// What every v3 screen shows until its chunk lands: the real progress header, wordmark, headline,
/// primary button and quiet links, wired to the real coordinator, so the whole flow can be walked
/// end to end while the screens are built in parallel.
///
/// Nothing in here ships as a screen. A chunk replaces its stub file and never edits this one.
struct OnboardingV3StubScreen: View {
    let step: OnboardingV3Step
    let coordinator: OnboardingV3Coordinator

    private var showsWordmark: Bool { step == .welcome || step == .auth }
    private var showsHeader: Bool { OnboardingProgressTable.value(for: step) != nil }

    private var headline: (lead: [String], accent: [String]) {
        let words = step.title.split(separator: " ").map(String.init)
        guard words.count > 1 else { return ([], words) }
        let split = words.count / 2
        return ([words[..<split].joined(separator: " ")], [words[split...].joined(separator: " ")])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                OnboardingProgressHeader(
                    step: step,
                    onSkip: step == .profileSetup || step == .claimCity ? { coordinator.advance() } : nil
                )
                .padding(.top, 9)
            } else if showsWordmark {
                AscendWordmark(height: 22, treatment: .onDark)
                    .padding(.top, 13)
                    .padding(.leading, 24)
            }

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 14) {
                Text("Screen \(stepNumber) of \(OnboardingV3Step.allCases.count) - stub")
                    .onboardingKicker()
                    .onboardingEntrance(index: 0)

                OnboardingHeadline(headline.lead, accentLines: headline.accent)
                    .onboardingEntrance(index: 1)

                Text("Its own build replaces this placeholder. The header, wordmark and buttons are the real kit.")
                    .onboardingBody()
                    .onboardingEntrance(index: 2)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            VStack(spacing: 4) {
                Button(step.primaryDestination == nil ? "Finish" : "Continue") {
                    coordinator.advance()
                }
                .buttonStyle(.onboardingPrimary)

                ForEach(step.alternateExits, id: \.title) { exit in
                    Button(exit.title) {
                        coordinator.go(to: exit.destination)
                    }
                    .buttonStyle(.onboardingQuietLink)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .onboardingEntrance(index: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stepNumber: Int {
        (OnboardingV3Step.allCases.firstIndex(of: step) ?? 0) + 1
    }
}

#Preview("Stub screen") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview") ?? .standard)))
}
