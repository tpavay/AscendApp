//
//  LeaderboardPodiumView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardPodiumView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entries: [ModeratedLeaderboardEntry]
    let metric: LeaderboardMetric
    var usesContainerBackground: Bool = false

    private var layout: ModeratedLeaderboardPodiumLayout {
        ModeratedLeaderboardPodiumLayout(entries: entries)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(layout.slots) { slot in
                podiumSlot(slot)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
        .padding(.horizontal, usesContainerBackground ? 14 : 0)
        .padding(.vertical, usesContainerBackground ? 14 : 0)
        .background {
            if usesContainerBackground {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark ? .white.opacity(0.04) : .black.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func podiumSlot(
        _ slot: ModeratedLeaderboardPodiumLayout.Slot
    ) -> some View {
        if let entry = slot.entry, !entry.isCurrentUser {
            NavigationLink {
                OtherUserProfileView(
                    identity: entry.identity,
                    moderationSource: .globalLeaderboard
                )
            } label: {
                LeaderboardPodiumSlotView(slot: slot, metric: metric)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .bottom)
        } else {
            LeaderboardPodiumSlotView(slot: slot, metric: metric)
                .frame(maxWidth: .infinity, alignment: .bottom)
        }
    }
}

private struct LeaderboardPodiumSlotView: View {
    @Environment(\.colorScheme) private var colorScheme

    let slot: ModeratedLeaderboardPodiumLayout.Slot
    let metric: LeaderboardMetric

    /// Which pedestal this is (1 centre, 2 left, 3 right). Drives geometry only.
    private var position: Int {
        slot.position
    }

    private var entry: ModeratedLeaderboardEntry? {
        slot.entry
    }

    /// The climber's true competition rank - what the label and medal reflect.
    private var rank: Int {
        slot.displayedRank
    }

    private var isTied: Bool {
        slot.isTied
    }

    private var avatarSize: CGFloat {
        position == 1 ? 88 : 68
    }

    private var topInset: CGFloat {
        position == 1 ? 0 : 26
    }

    private var medalColor: Color {
        switch rank {
        case 1:
            return LeaderboardMedal.gold
        case 2:
            return LeaderboardMedal.silver
        case 3:
            return LeaderboardMedal.bronze
        default:
            return colorScheme == .dark ? .white.opacity(0.72) : .black.opacity(0.62)
        }
    }

    private var ringGradient: AngularGradient {
        switch rank {
        case 1:
            return AngularGradient(
                colors: [
                    Color(red: 1.0, green: 0.93, blue: 0.46),
                    Color(red: 0.96, green: 0.75, blue: 0.16),
                    Color(red: 0.58, green: 0.39, blue: 0.04),
                    Color(red: 1.0, green: 0.93, blue: 0.46)
                ],
                center: .center
            )
        case 2:
            return AngularGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 1.0),
                    Color(red: 0.66, green: 0.70, blue: 0.78),
                    Color(red: 0.42, green: 0.46, blue: 0.54),
                    Color(red: 0.96, green: 0.97, blue: 1.0)
                ],
                center: .center
            )
        case 3:
            return AngularGradient(
                colors: [
                    Color(red: 0.98, green: 0.63, blue: 0.24),
                    Color(red: 0.78, green: 0.38, blue: 0.10),
                    Color(red: 0.47, green: 0.22, blue: 0.06),
                    Color(red: 0.98, green: 0.63, blue: 0.24)
                ],
                center: .center
            )
        default:
            return AngularGradient(
                colors: [.white.opacity(0.34), .white.opacity(0.12), .white.opacity(0.34)],
                center: .center
            )
        }
    }

    private var glowColor: Color {
        switch rank {
        case 1: return LeaderboardMedal.gold
        case 2: return LeaderboardMedal.silver
        case 3: return LeaderboardMedal.bronze
        default: return .clear
        }
    }

    private var displayName: String {
        entry?.identity.displayName ?? "Open"
    }

    private var valueColor: Color {
        rank == 1 ? LeaderboardMedal.gold : (colorScheme == .dark ? .white.opacity(0.78) : .black.opacity(0.72))
    }

    var body: some View {
        VStack(spacing: 5) {
            Spacer()
                .frame(height: topInset)

            if rank == 1 {
                crownMarker
            }

            avatar
                .frame(width: avatarSize, height: avatarSize)

            Text(CompetitionRanking.rankLabel(rank, isTied: isTied))
                .font(.montserratBold(size: position == 1 ? 38 : 32))
                .foregroundStyle(medalColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
                .accessibilityLabel(
                    CompetitionRanking.rankAccessibilityLabel(rank, isTied: isTied)
                )

            Text(displayName.uppercased())
                .font(.montserratBold(size: 11))
                .foregroundStyle(entry?.isCurrentUser == true ? .accent : (colorScheme == .dark ? .white.opacity(0.88) : .black.opacity(0.76)))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let entry {
                Text(entry.formattedValue)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityLabel("\(metric.displayName) \(entry.formattedValue)")
            } else {
                Text("CLAIM IT")
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.46))
                    .lineLimit(1)
            }
        }
        .frame(minHeight: position == 1 ? 184 : 176, alignment: .bottom)
    }

    private var crownMarker: some View {
        Image("LeaderboardCrown")
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .shadow(color: LeaderboardMedal.gold.opacity(colorScheme == .dark ? 0.48 : 0.26), radius: 6, x: 0, y: 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoURL = entry?.identity.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(.circle)
                case .failure:
                    placeholderAvatar
                case .empty:
                    placeholderAvatar
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.55)
                        )
                @unknown default:
                    placeholderAvatar
                }
            }
            .podiumRing(gradient: ringGradient, glow: glowColor, lineWidth: position == 1 ? 4 : 3, colorScheme: colorScheme)
            .id(photoURL)
        } else {
            placeholderAvatar
                .podiumRing(gradient: ringGradient, glow: glowColor, lineWidth: position == 1 ? 4 : 3, colorScheme: colorScheme)
        }
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08))
            .overlay(
                Image(systemName: entry == nil ? "sparkles" : "person.fill")
                    .font(.system(size: position == 1 ? 24 : 20, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.42))
            )
    }
}

private enum LeaderboardMedal {
    static let gold = Color(red: 0.96, green: 0.78, blue: 0.12)
    static let silver = Color(red: 0.74, green: 0.78, blue: 0.84)
    static let bronze = Color(red: 0.86, green: 0.48, blue: 0.16)
}

private extension View {
    func podiumRing(
        gradient: AngularGradient,
        glow: Color,
        lineWidth: CGFloat,
        colorScheme: ColorScheme
    ) -> some View {
        clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(gradient, lineWidth: lineWidth)
            )
            .overlay {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.54),
                                .clear,
                                .white.opacity(0.22),
                                .clear,
                                .white.opacity(0.48)
                            ],
                            center: .center
                        ),
                        lineWidth: 1.1
                    )
                    .padding(1.5)
            }
            .shadow(color: glow.opacity(colorScheme == .dark ? 0.54 : 0.28), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    LeaderboardPodiumView(
        entries: [
            .preview(userId: "1", displayName: "Jake M.", rank: 1, value: 21_482_991, formattedValue: "21,482,991"),
            .preview(userId: "2", displayName: "Sophia L.", rank: 2, value: 19_812_770, formattedValue: "19,812,770"),
            .preview(userId: "3", displayName: "Ethan D.", rank: 3, value: 17_926_441, formattedValue: "17,926,441")
        ],
        metric: .climb
    )
    .padding()
    .background(Color.black)
}
