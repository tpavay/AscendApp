import SwiftUI

/// The sign-in screen's list of what saves to the account: one row per item, each with its mark on
/// the left and a check on the right. Every row shown is something the climber gave or gets, so
/// every check is earned; a skipped item has no row (`OnboardingSavedItems`).
struct OnboardingSavedItemsCard: View {
    let items: [OnboardingSavedItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(OnboardingV3Palette.cardBorder)
                        .frame(height: 1)
                }

                OnboardingSavedItemRow(item: item)
            }
        }
        .padding(.horizontal, 14)
        .onboardingCard(cornerRadius: 22)
    }
}

private struct OnboardingSavedItemRow: View {
    let item: OnboardingSavedItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var subtitleSize: CGFloat = 12.5

    /// The mark and the check are glyphs, not text, so they hold their size: scaled with the text
    /// they ate the row's width at an accessibility size and left the words to break mid-word.
    private static let markSize: CGFloat = 44
    private static let checkSize: CGFloat = 26

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if isAccessibilitySize {
                // The text takes the full width under the mark, so a row still reads as one item.
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        mark
                        Spacer(minLength: 8)
                        check
                    }
                    text
                }
            } else {
                HStack(spacing: 12) {
                    mark
                    text
                    Spacer(minLength: 8)
                    check
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.subtitle)")
    }

    private var mark: some View {
        OnboardingSavedItemMark(kind: item.kind, initials: item.initials, photoURL: item.photoURL)
            .frame(width: Self.markSize, height: Self.markSize)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            // A title is one line in the design, shrinking a little for a long count; at an
            // accessibility size it wraps instead, because a shrunken line defeats the size.
            Text(item.title)
                .font(.custom("Montserrat-Bold", fixedSize: titleSize))
                .foregroundStyle(Color.white)
                .lineLimit(isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(isAccessibilitySize ? 1 : 0.72)

            Text(item.subtitle)
                .font(.custom("Montserrat-Medium", fixedSize: subtitleSize))
                .foregroundStyle(OnboardingV3Palette.secondary)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var check: some View {
        Image(systemName: "checkmark")
            .font(.system(size: Self.checkSize * 0.42, weight: .bold))
            .foregroundStyle(OnboardingV3Palette.secondary)
            .frame(width: Self.checkSize, height: Self.checkSize)
            .overlay(Circle().strokeBorder(OnboardingV3Palette.chipBorder, lineWidth: 1.5))
    }
}

/// The glyph for each kind. The climbs and the profile carry the full accent, the rest a tint of it,
/// the way the design weights the list.
///
/// The profile row is a picture of the climber, so it is a `ClimberAvatar`: the photo picked on the
/// profile screen when there is one, else the typed name's initials on the accent, else the
/// generic person on the accent, exactly as the design draws the three states.
private struct OnboardingSavedItemMark: View {
    let kind: OnboardingSavedItem.Kind
    let initials: String?
    let photoURL: URL?

    var body: some View {
        Group {
            if kind == .profile {
                ClimberAvatar(
                    userId: nil,
                    isCurrentUser: true,
                    photoURL: photoURL,
                    placeholder: .initials(
                        initials ?? "",
                        fill: OnboardingV3Palette.accent,
                        foreground: Color.black,
                        fontSize: 15
                    ),
                    size: 44,
                    showsChampionMark: false
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isEmphasised ? OnboardingV3Palette.accent : OnboardingV3Palette.accent.opacity(0.14))

                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isEmphasised ? Color.black : OnboardingV3Palette.accent)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var isEmphasised: Bool {
        switch kind {
        case .climbs, .profile: true
        case .healthHistory, .boards: false
        }
    }

    private var symbol: String {
        switch kind {
        case .climbs: "stairs"
        case .healthHistory: "chart.bar.fill"
        case .profile: PublicClimberIdentity.genericAvatarSystemName
        case .boards: "crown.fill"
        }
    }
}

#Preview("Saved items") {
    var answers = PreAuthOnboardingAnswers()
    answers.firstName = "Sam"
    answers.lastName = "Rivera"
    answers.gender = .man
    answers.birthday = PreAuthOnboardingBirthday(year: 1996, month: 3, day: 9)
    answers.city = PreAuthOnboardingCity(city: "Denver", region: "CO", countryCode: "US", countryName: "United States")
    answers.weeklyTargetDays = 4
    answers.recordFoundHealthHistory(HealthHistorySummary(
        workoutIDs: (0..<214).map { "w\($0)" },
        totalDuration: 0,
        workoutsWithSteps: 214,
        knownSteps: 698_240,
        bestHourSteps: nil,
        usualClimb: nil
    ))

    return VStack(spacing: 24) {
        OnboardingSavedItemsCard(items: OnboardingSavedItems.make(from: answers))
        OnboardingSavedItemsCard(items: OnboardingSavedItems.make(from: PreAuthOnboardingAnswers()))
    }
    .padding(24)
    .background(Color.black)
}
