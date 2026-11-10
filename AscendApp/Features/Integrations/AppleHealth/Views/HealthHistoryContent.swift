import SwiftUI

/// What a history screen says back about the workouts Health holds: the number they come to, the
/// one row that changes how far back the import reaches, and what those steps are the height of.
///
/// One body in two frames: onboarding's "We found your climbs" (07a) and Integrations' Import older
/// workouts. Everything it shows follows the range the climber picked.
struct HealthHistoryContent: View {
    let choice: HealthHistoryChoice

    @State private var isPickingRange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HealthHistoryHero(summary: choice.summary)

            HealthHistoryRangeRow(label: choice.rangeLabel) { isPickingRange = true }
                .onboardingEntrance(delay: 0.25, duration: 0.5)

            if let comparison = choice.comparison {
                HealthHistoryPeaksCard(comparison: comparison)
                    .onboardingEntrance(delay: 0.3, duration: 0.5)
            }

            HealthHistoryTiles(summary: choice.summary)
                .onboardingEntrance(delay: 0.45, duration: 0.5)
        }
        .sheet(isPresented: $isPickingRange) {
            HealthHistoryRangeSheet(choice: choice) { isPickingRange = false }
        }
    }
}

// MARK: - Range

/// The one tappable row under the number: how far back the import reaches.
private struct HealthHistoryRangeRow: View {
    let label: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 16

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.custom("Montserrat-ExtraBold", fixedSize: labelSize))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(OnboardingV3Palette.skip)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .onboardingCard(cornerRadius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Time range, \(label)")
        .accessibilityHint("Changes how far back workouts are added from")
    }
}

/// The range picker: everything, the last year, the last 90 days, or from a day.
///
/// A preset is one tap and the sheet closes. A range that holds no workouts cannot be picked, and
/// the date row only offers days that leave something to bring in, so the screen behind never has
/// nothing to add.
struct HealthHistoryRangeSheet: View {
    let choice: HealthHistoryChoice
    let onDone: () -> Void

    @State private var day: Date

    init(choice: HealthHistoryChoice, onDone: @escaping () -> Void) {
        self.choice = choice
        self.onDone = onDone
        if case .since(let picked) = choice.range {
            _day = State(initialValue: picked)
        } else {
            _day = State(initialValue: choice.pickableDays?.lowerBound ?? choice.now)
        }
    }

    var body: some View {
        ProfileSheetFrame(
            title: "How far back?",
            note: "Add the rest any time in Integrations.",
            onDone: onDone
        ) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(HealthHistoryChoice.presets, id: \.analyticsID) { range in
                        presetRow(range)
                    }

                    if let days = choice.pickableDays {
                        dateRow(days)
                    }
                }
                // Room for the chosen row's glow inside the scroll view, which would otherwise cut it
                // off square. The matching negative padding keeps the rows where they were.
                .padding(.vertical, Self.glowRoom)
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .padding(.vertical, -Self.glowRoom)
            .padding(.horizontal, -20)
        }
        .appSheetStyle(.detents([.height(Self.height), .large]))
    }

    /// Tall enough for the four rows above the home indicator at the standard text size. A larger
    /// size scrolls, and the sheet can be pulled to full height.
    static let height: CGFloat = 412
    private static let glowRoom: CGFloat = 16

    private func presetRow(_ range: HealthHistoryRange) -> some View {
        let count = choice.count(in: range)
        return OnboardingChoiceRow(
            title: Self.title(for: range),
            detail: Self.detail(count: count),
            isSelected: choice.range == range
        ) {
            HapticsManager.shared.trigger(.selection)
            choice.select(range)
            onDone()
        }
        .disabled(count == 0)
        .opacity(count == 0 ? 0.4 : 1)
    }

    private func dateRow(_ days: ClosedRange<Date>) -> some View {
        let isSelected = if case .since = choice.range { true } else { false }
        return HStack(spacing: 12) {
            Text("Since")
                .font(.custom("Montserrat-ExtraBold", size: 17, relativeTo: .body))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker("Since", selection: $day, in: days, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(OnboardingV3Palette.accent)
                .colorScheme(.dark)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? OnboardingV3Palette.accent.opacity(0.1) : OnboardingV3Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isSelected ? OnboardingV3Palette.accent : OnboardingV3Palette.cardBorder,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .onChange(of: day) { _, picked in
            choice.select(.since(picked))
        }
    }

    static func title(for range: HealthHistoryRange) -> String {
        switch range {
        case .everything: "Everything"
        case .lastYear: "Last year"
        case .last90Days: "Last 90 days"
        case .since: "Since"
        }
    }

    static func detail(count: Int) -> String {
        switch count {
        case 0: "None"
        case 1: "1 workout"
        default: "\(count.formatted()) workouts"
        }
    }
}

// MARK: - Hero

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
        let reporting = summary.workoutsWithSteps == 1 ? "the 1 that has them" : "the \(summary.workoutsWithSteps.formatted()) that have them"
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
        .onAppear { count(to: target, over: 1.6) }
        // A new range is a new number, and it counts there from the one it was showing.
        .onChange(of: target) { _, newTarget in count(to: newTarget, over: 0.6) }
    }

    private func count(to value: Double, over seconds: Double) {
        if reduceMotion {
            shown = value
        } else {
            withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: seconds)) { shown = value }
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
