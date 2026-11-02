import SwiftUI

struct HomeStartActionSheet: View {
    let onSelect: (HomeStartAction) -> Void
    /// Nil when logging is switched off.
    let onLogIt: (() -> Void)?
    /// What the Health button says, or nil where import is not on offer (no Health on the device,
    /// or the kill switch off). With both this and `onLogIt` nil, the whole section goes away.
    var healthEntry: AppleHealthEntry?
    var onHealth: () -> Void = {}

    var body: some View {
        AppSheetScaffold(
            title: "START",
            message: "Climb now, race a landmark, or run intervals.",
            headerAlignment: .leading,
            contentAlignment: .leading,
            layout: .actionMenu
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(HomeStartAction.allCases, id: \.self) { action in
                    HomeStartActionRow(action: action, onSelect: onSelect)
                }

                if onLogIt != nil || healthEntry != nil {
                    alreadyClimbed
                        .padding(.top, 10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .trackOnce(screen: .homeStartAction)
    }

    /// Logging and importing are the second way to land a climb, not a fourth way to start one,
    /// so they sit apart from the three rows above and say what they are for.
    private var alreadyClimbed: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALREADY CLIMBED?")
                .font(.montserratBold(size: 11))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 10) {
                if let onLogIt {
                    secondaryButton(action: onLogIt) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
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
                            .frame(width: 24, height: 24)
                            .clipShape(.rect(cornerRadius: 6))
                            .accessibilityHidden(true)
                        Text(healthEntry.title)
                            .font(.montserratBold(size: 14))
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
            HStack(spacing: 8) {
                label()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
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
