import SwiftUI

struct HomeStartActionSheet: View {
    let onSelect: (HomeStartAction) -> Void
    /// Nil when logging is switched off.
    let onLogIt: (() -> Void)?
    /// What the Health button says, or nil where import is not on offer (no Health on the device,
    /// or the kill switch off). With both this and `onLogIt` nil, the whole section goes away.
    var healthEntry: AppleHealthEntry?
    var onHealth: () -> Void = {}
    /// Today's landmark and routine, named on their rows.
    var picks: HomeStartPicks = .none
    var onSeeAll: (HomeStartAction) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ForEach(HomeStartAction.allCases, id: \.self) { action in
                HomeStartActionRow(
                    action: action,
                    detail: picks.line(for: action),
                    onSelect: onSelect,
                    onSeeAll: onSeeAll
                )
            }

            if onLogIt != nil || healthEntry != nil {
                alreadyClimbed
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSheetBackground()
        .preferredColorScheme(.dark)
        .trackOnce(screen: .homeStartAction)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CLIMB")
                .font(.montserratBold(size: 30))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            Text("Pick how today goes")
                .font(.montserratSemiBold(size: 13))
                .foregroundStyle(Color(white: 0.56))
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    /// Logging and importing are the second way to land a climb, not a fourth way to start one,
    /// so they sit apart from the three rows above and say what they are for.
    private var alreadyClimbed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ALREADY CLIMBED?")
                .font(.montserratBold(size: 12))
                .tracking(1.7)
                .foregroundStyle(Color(white: 0.56))
                .padding(.horizontal, 6)
                .padding(.top, 6)

            HStack(spacing: 10) {
                if let onLogIt {
                    secondaryButton(action: onLogIt) {
                        HomeStartPencilShape()
                            .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        Text("Log it")
                            .font(.montserratBold(size: 14))
                    }
                    .accessibilityHint("Type in a climb you did without a live session")
                }

                if let healthEntry {
                    secondaryButton(action: onHealth) {
                        Image("appleHealth-icon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 26, height: 26)
                            .clipShape(.rect(cornerRadius: 7))
                            .accessibilityHidden(true)
                        Text(healthEntry.title)
                            .font(.montserratBold(size: 14))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .overlay(alignment: .topTrailing) {
                        if case .viewImports(let badge) = healthEntry, badge > 0 {
                            HealthCountBadge(count: badge)
                                .offset(x: 6, y: -8)
                        }
                    }
                    .accessibilityLabel(healthEntry.accessibilityLabel)
                    .accessibilityHint(healthEntry.accessibilityHint)
                }
            }
        }
    }

    private func secondaryButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                label()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.067))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(white: 0.165), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

extension AppleHealthEntry {
    var title: String {
        switch self {
        case .connect:
            return "Connect Health"
        case .viewImports:
            return "View imports"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .connect:
            return "Connect Health"
        case .viewImports(let badge):
            return badge > 0 ? "View imports, \(badge) waiting" : "View imports"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .connect:
            return "Connect Apple Health to bring in stair stepper workouts"
        case .viewImports:
            return "Opens the stair stepper workouts Apple Health holds"
        }
    }
}

#Preview {
    HomeStartActionSheet(onSelect: { _ in }, onLogIt: {})
}
