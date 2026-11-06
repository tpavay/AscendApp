import SwiftUI

/// One of the three example climbers the sign-in board shows on top.
///
/// They are fixed: the board is a picture of what the weekly Steps board looks like, drawn with
/// avatars the earlier onboarding already ships. No read, no network and no real climber is
/// involved, so there is no identity to moderate and nothing to go stale.
struct OnboardingAuthExampleClimber: Equatable, Identifiable {
    let rank: Int
    let name: String
    let steps: String
    let avatarImageName: String

    var id: Int { rank }

    static let weeklyTopThree = [
        OnboardingAuthExampleClimber(rank: 1, name: "Mason D.", steps: "38,891", avatarImageName: "OnboardingLeaderboardAvatarMaya"),
        OnboardingAuthExampleClimber(rank: 2, name: "Noah R.", steps: "12,335", avatarImageName: "OnboardingLeaderboardAvatarNoah"),
        OnboardingAuthExampleClimber(rank: 3, name: "Ava M.", steps: "9,720", avatarImageName: "OnboardingLeaderboardAvatarAva")
    ]
}

/// The board on the sign-in screen: this week's header and countdown, three example climbers, and
/// the climber's own empty row waiting under them.
///
/// The climber's row is never a text field: it carries no caret and no prompt to type a name,
/// because Ascend never asks for one (`SuppliedNameAdoption`).
struct OnboardingAuthBoardCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)

            ForEach(OnboardingAuthExampleClimber.weeklyTopThree) { climber in
                OnboardingAuthBoardRow(climber: climber)
            }

            OnboardingAuthYouRow()
                .padding(.top, 6)
        }
        .padding(14)
        .onboardingCard(cornerRadius: 24)
        // A board is dense by nature: at an accessibility size a name and a total would each
        // truncate to a letter. Capped at the largest ordinary size, the rows stay whole and the
        // headline, kicker and buttons around the card carry the larger text.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("This week \u{00B7} Steps")
                .onboardingKicker(color: OnboardingV3Palette.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            LeaderboardCountdownLabel(currentPeriodOf: .weekly, fontSize: 11)
        }
    }
}

private struct OnboardingAuthBoardRow: View {
    let climber: OnboardingAuthExampleClimber

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 38
    @ScaledMetric(relativeTo: .body) private var rankWidth: CGFloat = 22

    var body: some View {
        HStack(spacing: 12) {
            Text(climber.rank.formatted())
                .font(.custom("Montserrat-ExtraBold", fixedSize: 17))
                .foregroundStyle(medal)
                .frame(width: rankWidth, alignment: .leading)

            Image(climber.avatarImageName)
                .resizable()
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(medal, lineWidth: 2))
                .accessibilityHidden(true)

            Text(climber.name)
                .font(.custom("Montserrat-Bold", size: 17, relativeTo: .body))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Text(climber.steps)
                .font(.custom("Montserrat-Bold", size: 17, relativeTo: .body))
                .foregroundStyle(OnboardingV3Palette.body)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Rank \(climber.rank), \(climber.name), \(climber.steps) steps this week"
        )
    }

    private var medal: Color {
        switch climber.rank {
        case 1: OnboardingV3Palette.gold
        case 2: Color(hex: "C0C0C0")
        default: Color(hex: "CD7F32")
        }
    }
}

/// The climber's own row: dashed, lime and pulsing, a question mark where a rank will go and a
/// zero where their steps will be. It is a promise, not an input.
struct OnboardingAuthYouRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 38
    @ScaledMetric(relativeTo: .body) private var rankWidth: CGFloat = 22
    @State private var isDimmed = false

    var body: some View {
        HStack(spacing: 12) {
            Text("?")
                .font(.custom("Montserrat-ExtraBold", fixedSize: 17))
                .foregroundStyle(OnboardingV3Palette.accent)
                .frame(width: rankWidth, alignment: .leading)

            Text("YOU")
                .font(.custom("Montserrat-Black", fixedSize: 12))
                .tracking(0.6)
                .foregroundStyle(.black)
                .frame(width: avatarSize, height: avatarSize)
                .background(Circle().fill(OnboardingV3Palette.accent))

            Text("You")
                .font(.custom("Montserrat-Bold", size: 17, relativeTo: .body))
                .foregroundStyle(OnboardingV3Palette.accent)

            Spacer(minLength: 8)

            Text("0")
                .font(.custom("Montserrat-Bold", size: 17, relativeTo: .body))
                .foregroundStyle(OnboardingV3Palette.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(OnboardingV3Palette.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    OnboardingV3Palette.accent,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .opacity(isDimmed ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You, not ranked yet, 0 steps. Sign in to claim your spot.")
    }
}
