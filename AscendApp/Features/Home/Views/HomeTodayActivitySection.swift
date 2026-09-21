import SwiftUI

/// ON THE GLOBE TODAY: the three most recent uploaded climbs of any kind, each a door
/// into the real climb, with SEE ALL when the server holds more.
///
/// Nothing renders until the first feed snapshot has landed: an empty state that
/// reads "nobody has climbed" before the server has answered would be a claim the
/// app has not checked.
struct HomeTodayActivitySection: View {
    let rows: [ModeratedHomeTodayActivityRow]
    let presentations: [String: HomeTodayActivityRowPresentation]
    let hasReceivedFeed: Bool
    let showsSeeAll: Bool
    let onOpen: (ModeratedHomeTodayActivityRow, HomeTodayActivityRowPresentation) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        if hasReceivedFeed {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ClimbBrowseSectionHeader(title: "On the Globe Today")

                Spacer(minLength: 0)

                if showsSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 4) {
                            Text("SEE ALL")
                                .font(.montserratBold(size: 11))
                                .tracking(0.8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all climbs on the globe today")
                }
            }

            if rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        if let presentation = presentations[row.id] {
                            HomeTodayActivityRowView(row: row, presentation: presentation) {
                                onOpen(row, presentation)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Text("No climbs on the globe yet today. Be the first up.")
            .font(.montserratMedium(size: 13))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
    }
}

/// One today row: who, what they climbed, how it went, how long ago.
struct HomeTodayActivityRowView: View {
    let row: ModeratedHomeTodayActivityRow
    let presentation: HomeTodayActivityRowPresentation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.identity.displayName)
                        .font(.montserratSemiBold(size: 13.5))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(presentation.title) · \(presentation.detail)")
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if presentation.isTappable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(!presentation.isTappable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.identity.displayName): \(presentation.title), \(presentation.detail)")
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        switch presentation.destination {
        case .climbDetail:
            return "Open climb detail"
        case .justClimb:
            return "Start the same Just Climb"
        case .routineTemplate:
            return "Open the routine in Training"
        case .none:
            return ""
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoURL = row.identity.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    avatarToken
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
        } else {
            avatarToken
        }
    }

    private var avatarToken: some View {
        Group {
            if row.identity.avatarToken.isEmpty {
                Image(systemName: PublicClimberIdentity.genericAvatarSystemName)
                    .font(.system(size: 15, weight: .semibold))
            } else {
                Text(row.identity.avatarToken)
                    .font(.montserratBold(size: 12))
            }
        }
        .foregroundStyle(row.isCurrentUser ? .black : .white)
        .frame(width: 38, height: 38)
        .background(Circle().fill(row.isCurrentUser ? Color.accent : Color.white.opacity(0.14)))
        .accessibilityHidden(true)
    }
}
