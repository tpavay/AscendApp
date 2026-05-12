import SwiftUI

struct WorkoutLiveClimbShareCard: View {
    let workout: Workout
    let climb: Climb
    let rank: Int?
    let rankTotal: Int?
    var isRankLoading = false
    var bestEffortText: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background(in: geometry.size)
                content(in: geometry.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: climb.tier.borderColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .opacity(0.9)
            }
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.black)
                    .shadow(color: climb.tier.shadowColor.opacity(0.32), radius: 18)
            )
        }
    }

    private func background(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            Color.black

            ClimbArtworkView(climb: climb, variant: .hero)
                .frame(width: size.width, height: size.height * 0.66)
                .clipped()
                .frame(maxHeight: .infinity, alignment: .top)

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.54),
                    .black.opacity(0.96),
                    .black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func content(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: size.height * 0.44)

            HStack(alignment: .top, spacing: 18) {
                rankBlock
                    .frame(width: size.width * 0.28, alignment: .leading)

                statGrid
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            if let bestEffortText {
                bestEffortBanner(bestEffortText)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)
            }

            VStack(spacing: 4) {
                Text(climb.name)
                    .font(.montserratBold(size: 27))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(climb.displayLocation)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
    }

    private func bestEffortBanner(_ text: String) -> some View {
        HStack(spacing: 5) {
            AppIcon(token: .bestEffortTrophy, pointSize: 10, weight: .bold)
                .foregroundStyle(.accent.opacity(0.9))

            Text(text.uppercased())
                .font(.montserratBold(size: 7.4))
                .tracking(0.8)
                .foregroundStyle(.accent.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.black.opacity(0.5))
                .overlay(
                    Capsule()
                        .stroke(.accent.opacity(0.24), lineWidth: 0.8)
                )
        )
    }

    private var rankBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rank == nil && !isRankLoading ? "LIVE CLIMB" : "GLOBAL RANK")
                .font(.montserratBold(size: 8))
                .foregroundStyle(.accent.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(rankText)
                .font(.montserratBold(size: rank == nil ? 24 : 42))
                .foregroundStyle(.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            if let rankTotal, rankTotal > 0 {
                Text("OUT OF \(rankTotal.formatted())")
                    .font(.montserratBold(size: 7))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 18),
                GridItem(.flexible(), spacing: 18)
            ],
            alignment: .leading,
            spacing: 10
        ) {
            shareStat(title: "TOTAL STEPS", value: workout.steps.formatted())
            shareStat(title: "STEPS PER MINUTE", value: averageSPMText)
            shareStat(title: "ELAPSED TIME", value: workout.durationFormatted)

            if let calories = workout.caloriesBurned, calories > 0 {
                shareStat(title: "CALORIES BURNED", value: calories.formatted())
            } else {
                shareStat(title: "FLOORS", value: workout.floors.formatted())
            }
        }
    }

    private func shareStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.montserratBold(size: 7.5))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(value)
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
    }

    private var rankText: String {
        if isRankLoading {
            return "..."
        }

        guard let rank else { return "DONE" }
        return rank.ordinalText
    }

    private var averageSPMText: String {
        guard let pace = workout.pace(for: .steps), pace > 0 else { return "0" }
        return Int(pace.rounded()).formatted()
    }
}

private extension Int {
    var ordinalText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

#Preview {
    WorkoutLiveClimbShareCard(
        workout: Workout(
            name: "Mount Etna Live Climb",
            duration: 2_712,
            steps: 809,
            floors: 41,
            caloriesBurned: 420,
            source: .headphoneMotion
        ),
        climb: .preview,
        rank: 12,
        rankTotal: 2_460
    )
    .frame(width: 344, height: 344)
    .padding()
    .background(.black)
}
