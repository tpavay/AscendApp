import SwiftUI

/// Everyone's period: the whole community's climbs, steps and climbers, over a landmark.
struct PeriodRecapEveryonePage: View {
    @Environment(\.recapIsStatic) private var isStatic

    let summary: PeriodRecapCommunity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
                .frame(maxHeight: 150)

            if summary.community.climbers == 0 {
                Text("Nobody climbed \(PeriodRecapCopy.periodSubject(for: summary.period)).")
                    .font(.montserratBold(size: 30))
                    .foregroundStyle(.white)
                    .recapEntrance(0)
            } else {
                Text("Everyone climbed.")
                    .font(.montserratBold(size: 30))
                    .foregroundStyle(.white)
                    .padding(.bottom, 18)
                    .recapEntrance(0)

                stat(summary.community.climbs, label: "CLIMBS", order: 1)
                stat(summary.community.steps, label: "STEPS", order: 2)
                stat(summary.community.climbers, label: "CLIMBERS", order: 3)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: Int, label: String, order: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RecapCountUpText(
                value: value,
                font: .montserratBold(size: 50),
                delay: Double(order) * 0.08,
                isStatic: isStatic
            )
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)

            RecapSectionLabel(label, color: .white.opacity(0.62))
        }
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
        .recapEntrance(order)
    }
}

/// The landmark behind everyone's period, picked by period so it changes week to week.
struct PeriodRecapLandmarkBackground: View {
    static let landmarks = [
        "OnboardingLandmarkEmpireCard",
        "OnboardingLandmarkBurjCard",
        "OnboardingLandmarkEiffelCard",
        "OnboardingLandmarkStatueCard",
        "OnboardingLandmarkEverestCard"
    ]

    let period: LeaderboardPeriod

    private var imageName: String {
        Self.landmarks[StableAvatarPalette.index(for: period.key, count: Self.landmarks.count)]
    }

    var body: some View {
        // The photo fills as an overlay on a view that takes exactly the proposal, so its
        // scaled size can never widen the story laid out over it.
        Color.black
            .overlay {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.35), location: 0),
                        .init(color: .black.opacity(0.92), location: 0.62),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
