import SwiftUI

/// The two in-session views the user can toggle between once a live climb is
/// recording. "Just Me" is the solo stats view; "Leaderboard" is the live race
/// ranking.
enum LiveClimbSessionTab: String, CaseIterable, Identifiable {
    case justMe
    case leaderboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .justMe:
            return "Just Me"
        case .leaderboard:
            return "Leaderboard"
        }
    }
}

/// Segmented toggle shown across the top of the live session while recording.
struct LiveClimbSessionTabBar: View {
    @Binding var selection: LiveClimbSessionTab
    var tint: Color = .accent

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LiveClimbSessionTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(selection == tab ? .black : .white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            Capsule()
                                .fill(selection == tab ? tint : .clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}
