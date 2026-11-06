import SwiftUI

/// 07a We found your climbs: what Apple Health already holds, said back to the climber before they
/// have an account.
///
/// It only looks. ADD TO MY HISTORY records which workouts the climber agreed to bring in and moves
/// on; the import runs after sign-in, when there is an account to put them in, and it files them
/// off the leaderboards, which is what the line above the button says.
struct OnboardingHealthHistoryScreen: View {
    let coordinator: OnboardingV3Coordinator

    @State private var viewModel: OnboardingHealthHistoryViewModel

    init(coordinator: OnboardingV3Coordinator, viewModel: OnboardingHealthHistoryViewModel? = nil) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: viewModel ?? OnboardingHealthHistoryViewModel())
    }

    var body: some View {
        OnboardingSetupLayout(step: .healthHistory) {
            switch viewModel.state {
            case .loading, .nothing:
                // Nothing to draw until the read answers. A read that found nothing hands the climber
                // to the usual-climb question below, so this is never a screen to read.
                Color.clear.frame(height: 1)
            case .found(let summary):
                HealthHistoryBody(summary: summary, comparison: viewModel.comparison)
            }
        } footer: {
            VStack(spacing: 10) {
                Text(Self.footnote)
                    .font(.custom("Montserrat-SemiBold", fixedSize: 12))
                    .foregroundStyle(Color(hex: "8E8E8E"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .onboardingEntrance(delay: 0.6)

                Button("Add to my history") { viewModel.addToHistory(coordinator: coordinator) }
                    .buttonStyle(.onboardingPrimary)
                    .disabled(summary == nil)
            }
            // Solid, so a body that scrolls under it at a large text size is cut clean, not read through.
            .background(OnboardingV3Palette.background)
        }
        .task { await viewModel.load(coordinator: coordinator) }
        .trackOnce(screen: .onboardingHealthHistory)
    }

    static let footnote = "Past climbs fill your history and personal bests. Every climb after you sign up counts on the leaderboards."

    private var summary: HealthHistorySummary? {
        if case .found(let summary) = viewModel.state { return summary }
        return nil
    }
}

// MARK: - Body

private struct HealthHistoryBody: View {
    let summary: HealthHistorySummary
    let comparison: HealthHistoryComparison?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HealthHistoryHero(summary: summary)

            if let comparison {
                HealthHistoryPeaksCard(comparison: comparison)
                    .onboardingEntrance(delay: 0.3, duration: 0.5)
            }

            HealthHistoryTiles(summary: summary)
                .onboardingEntrance(delay: 0.45, duration: 0.5)
        }
    }
}

/// "WE FOUND YOUR CLIMBS" over the number the history comes to, which counts up from zero.
private struct HealthHistoryHero: View {
    let summary: HealthHistorySummary

    @OnboardingReduceMotion private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 60
    @State private var shown: Double = 0

    private var target: Double {
        Double(summary.leadsWithSteps ? summary.knownSteps : summary.workoutCount)
    }

    private var workoutsPhrase: String {
        summary.workoutCount == 1 ? "1 stair stepper workout" : "\(summary.workoutCount.formatted()) stair stepper workouts"
    }

    private var subtitle: String {
        summary.leadsWithSteps
            ? "steps in \(workoutsPhrase)"
            : "stair stepper \(summary.workoutCount == 1 ? "workout" : "workouts") · \(summary.totalDurationText)"
    }

    /// The steps behind a headline that led with the workouts, said once and only when some exist.
    private var stepsNote: String? {
        guard !summary.leadsWithSteps, summary.knownSteps > 0 else { return nil }
        let reporting = summary.workoutsWithSteps == 1 ? "the 1 that tracks them" : "the \(summary.workoutsWithSteps.formatted()) that track them"
        return "\(summary.knownSteps.formatted()) steps in \(reporting)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("We found your climbs")
                .onboardingKicker()
                .onboardingEntrance(index: 0)

            CountUpNumber(value: shown)
                .font(.custom("Montserrat-Black", fixedSize: numberSize))
                .tracking(-numberSize * 0.04)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onboardingEntrance(delay: 0.1)

            Text(subtitle)
                .font(.custom("Montserrat-Bold", fixedSize: 16))
                .foregroundStyle(Color(hex: "CFCFCF"))
                .fixedSize(horizontal: false, vertical: true)
                .onboardingEntrance(delay: 0.15)

            if let stepsNote {
                Text(stepsNote)
                    .onboardingSecondary()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .onboardingEntrance(delay: 0.2)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "We found your climbs. \(summary.leadsWithSteps ? summary.knownSteps.formatted() : summary.workoutCount.formatted()) \(subtitle)"
                + (stepsNote.map { ". \($0)" } ?? "")
        )
        .onAppear {
            if reduceMotion {
                shown = target
            } else {
                withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 1.6)) { shown = target }
            }
        }
    }
}

/// A number that counts because its value animates.
private struct CountUpNumber: View, Animatable {
    nonisolated var value: Double

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Int(value.rounded()).formatted())
            .monospacedDigit()
    }
}

// MARK: - Peaks

/// "THAT'S EVEREST": one peak for each time the steps climb it, growing in one after another.
private struct HealthHistoryPeaksCard: View {
    let comparison: HealthHistoryComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(comparison.kicker)
                .onboardingKicker(color: Color(hex: "9A9A9A"))

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<comparison.peakCount, id: \.self) { index in
                    HealthPeak(index: index)
                }
            }
            .frame(height: 42)
            .accessibilityHidden(true)

            Text(comparison.timesOverText)
                .font(.custom("Montserrat-Black", fixedSize: 22))
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingCard(cornerRadius: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(comparison.kicker). \(comparison.timesOverText)")
    }
}

/// One triangle, in the design's three heights, scaling up from its base half a second after the
/// card arrives and 0.05 s after the peak beside it.
private struct HealthPeak: View {
    let index: Int

    @OnboardingReduceMotion private var reduceMotion
    @State private var hasGrown = false

    private var height: CGFloat { CGFloat(26 + (index % 3) * 8) }

    var body: some View {
        PeakShape()
            .fill(LinearGradient(
                colors: [Color(hex: "E8FFC2"), OnboardingV3Palette.progressFillStart],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .scaleEffect(y: hasGrown || reduceMotion ? 1 : 0, anchor: .bottom)
            .opacity(hasGrown || !reduceMotion ? 1 : 0)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .onAppear {
                let delay = 0.5 + 0.05 * Double(index)
                withAnimation(.timingCurve(0.2, 0.9, 0.3, 1.1, duration: 0.5).delay(reduceMotion ? 0 : delay)) {
                    hasGrown = true
                }
            }
    }
}

private struct PeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Tiles

/// "YOUR BEST HOUR" (gold) and "YOUR USUAL CLIMB". With no workout long enough to read an hour from,
/// the usual climb takes the whole row.
private struct HealthHistoryTiles: View {
    let summary: HealthHistorySummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let bestHour = summary.bestHourSteps {
                HealthHistoryTile(
                    kicker: "Your best hour",
                    value: bestHour.formatted(),
                    caption: "steps in 60 min",
                    tone: .gold
                )
            }

            if let usual = summary.usualClimb {
                HealthHistoryTile(
                    kicker: "Your usual climb",
                    value: usual.steps?.formatted() ?? usual.minutes.formatted(),
                    caption: usual.steps == nil ? "minutes" : "steps · \(usual.minutes) min",
                    tone: .plain
                )
            }
        }
    }
}

private struct HealthHistoryTile: View {
    enum Tone { case gold, plain }

    let kicker: String
    let value: String
    let caption: String
    let tone: Tone

    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 22

    private var kickerColor: Color {
        tone == .gold ? Color(hex: "E8C34A") : Color(hex: "9A9A9A")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(.custom("Montserrat-ExtraBold", fixedSize: 10))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(kickerColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.custom("Montserrat-Black", fixedSize: valueSize))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(caption)
                .font(.custom("Montserrat-SemiBold", fixedSize: 12))
                .foregroundStyle(OnboardingV3Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    tone == .gold
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color(hex: "E8C34A").opacity(0.14), OnboardingV3Palette.cardFill],
                            startPoint: UnitPoint(x: 0.2, y: 0),
                            endPoint: UnitPoint(x: 0.7, y: 0.8)
                        ))
                        : AnyShapeStyle(OnboardingV3Palette.cardFill)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tone == .gold ? Color(hex: "4A3E16") : OnboardingV3Palette.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kicker). \(value) \(caption)")
    }
}

#Preview("07a we found your climbs") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-health-history") ?? .standard),
        startingAt: .healthHistory
    ))
}
