import SwiftUI

struct HomeStartActionSheet: View {
    let onSelect: (HomeStartAction) -> Void
    /// Nil when logging is switched off, which takes the whole section away.
    let onLogIt: (() -> Void)?

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

                if let onLogIt {
                    alreadyClimbed(onLogIt: onLogIt)
                        .padding(.top, 10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .trackOnce(screen: .homeStartAction)
    }

    /// Logging is the second way to land a climb, not a fourth way to start one, so it sits apart
    /// from the three rows above and says what it is for.
    private func alreadyClimbed(onLogIt: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALREADY CLIMBED?")
                .font(.montserratBold(size: 11))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))

            Button(action: onLogIt) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                    Text("Log it")
                        .font(.montserratBold(size: 14))
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
            .accessibilityHint("Type in a climb you did without a live session")
        }
    }
}

#Preview {
    HomeStartActionSheet(onSelect: { _ in }, onLogIt: {})
}
