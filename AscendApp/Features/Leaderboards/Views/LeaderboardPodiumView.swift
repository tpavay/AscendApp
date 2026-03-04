//
//  LeaderboardPodiumView.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardPodiumView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var settingsManager = SettingsManager.shared

    let entries: [LeaderboardEntry]
    let metric: LeaderboardMetric
    var usesContainerBackground: Bool = true

    private struct PodiumSlot: Identifiable {
        let rank: Int
        let entry: LeaderboardEntry?

        var id: Int { rank }
    }

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var podiumSlots: [PodiumSlot] {
        let topRanks = entries
            .filter { $0.rank <= 3 }
            .reduce(into: [Int: LeaderboardEntry]()) { partialResult, entry in
                partialResult[entry.rank] = entry
            }

        return [2, 1, 3].map { rank in
            PodiumSlot(rank: rank, entry: topRanks[rank])
        }
    }

    private var missingSlotCount: Int {
        podiumSlots.filter { $0.entry == nil }.count
    }

    private var waitingMessage: String {
        switch missingSlotCount {
        case 1:
            return "One podium spot is open. Waiting for a challenger."
        case 2:
            return "Two podium spots are open. Bring the competition."
        case 3:
            return "Podium is waiting for challengers."
        default:
            return ""
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(podiumSlots) { slot in
                    PodiumSlotView(
                        rank: slot.rank,
                        entry: slot.entry,
                        metric: metric,
                        preferredMetric: preferredMetric,
                        colorScheme: colorScheme
                    )
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .background {
                if usesContainerBackground {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color(red: 0.14, green: 0.15, blue: 0.17) : .white,
                                    colorScheme == .dark ? Color(red: 0.09, green: 0.09, blue: 0.11) : .white
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06), lineWidth: 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(Color.accent.opacity(colorScheme == .dark ? 0.18 : 0.1))
                                .blur(radius: 34)
                                .frame(width: 120, height: 120)
                                .offset(x: 22, y: -28)
                        }
                }
            }

            if missingSlotCount > 0 {
                Text(waitingMessage)
                    .font(.montserratMedium(size: 12))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.6) : .gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
        .padding(.horizontal, usesContainerBackground ? 20 : 0)
    }
}

private struct PodiumSlotView: View {
    let rank: Int
    let entry: LeaderboardEntry?
    let metric: LeaderboardMetric
    let preferredMetric: WorkoutMetric
    let colorScheme: ColorScheme

    private var avatarSize: CGFloat {
        rank == 1 ? 76 : 60
    }

    private var pedestalHeight: CGFloat {
        switch rank {
        case 1: return 118
        case 2: return 94
        case 3: return 86
        default: return 72
        }
    }

    private var pedestalFill: LinearGradient {
        switch rank {
        case 1:
            return LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.90, blue: 0.52),
                    Color(red: 0.92, green: 0.70, blue: 0.22),
                    Color(red: 0.60, green: 0.43, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 2:
            return LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.95, blue: 0.98),
                    Color(red: 0.74, green: 0.78, blue: 0.85),
                    Color(red: 0.54, green: 0.58, blue: 0.66)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 3:
            return LinearGradient(
                colors: [
                    Color(red: 0.84, green: 0.61, blue: 0.38),
                    Color(red: 0.72, green: 0.45, blue: 0.23),
                    Color(red: 0.48, green: 0.30, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.18),
                    Color.white.opacity(colorScheme == .dark ? 0.1 : 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var rankColor: Color {
        switch rank {
        case 1:
            return .black.opacity(0.45)
        case 2:
            return .black.opacity(0.42)
        case 3:
            return .white.opacity(0.72)
        default:
            return colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.5)
        }
    }

    private var valueColor: Color {
        switch rank {
        case 1:
            return Color(red: 0.94, green: 0.78, blue: 0.26)
        case 2:
            return colorScheme == .dark ? .white : .black
        case 3:
            return colorScheme == .dark ? .white : .black
        default:
            return colorScheme == .dark ? .white : .black
        }
    }

    private var pedestalStrokeColor: Color {
        switch rank {
        case 1:
            return Color(red: 0.95, green: 0.77, blue: 0.32).opacity(0.95)
        case 2:
            return Color(red: 0.89, green: 0.92, blue: 0.99).opacity(0.9)
        case 3:
            return Color(red: 0.88, green: 0.63, blue: 0.36).opacity(0.9)
        default:
            return isCurrentUser ? Color.accent.opacity(0.55) : .white.opacity(0.08)
        }
    }

    private var medalRingGradient: AngularGradient {
        switch rank {
        case 1:
            return AngularGradient(
                colors: [
                    Color(red: 1.0, green: 0.94, blue: 0.62),
                    Color(red: 0.95, green: 0.76, blue: 0.24),
                    Color(red: 0.68, green: 0.50, blue: 0.09),
                    Color(red: 1.0, green: 0.94, blue: 0.62)
                ],
                center: .center
            )
        case 2:
            return AngularGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color(red: 0.74, green: 0.78, blue: 0.86),
                    Color(red: 0.55, green: 0.60, blue: 0.68),
                    Color(red: 0.98, green: 0.99, blue: 1.0)
                ],
                center: .center
            )
        case 3:
            return AngularGradient(
                colors: [
                    Color(red: 0.93, green: 0.71, blue: 0.48),
                    Color(red: 0.72, green: 0.45, blue: 0.24),
                    Color(red: 0.49, green: 0.30, blue: 0.16),
                    Color(red: 0.93, green: 0.71, blue: 0.48)
                ],
                center: .center
            )
        default:
            return AngularGradient(
                colors: [Color.white.opacity(0.35), Color.white.opacity(0.15), Color.white.opacity(0.35)],
                center: .center
            )
        }
    }

    private var medalRingGlow: Color {
        switch rank {
        case 1: return Color(red: 0.96, green: 0.78, blue: 0.25)
        case 2: return Color(red: 0.79, green: 0.83, blue: 0.92)
        case 3: return Color(red: 0.79, green: 0.50, blue: 0.28)
        default: return .white
        }
    }

    private var pedestalShine: LinearGradient {
        switch rank {
        case 1:
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.98, blue: 0.75).opacity(0.55),
                    Color(red: 1.0, green: 0.86, blue: 0.45).opacity(0.18),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 2:
            return LinearGradient(
                colors: [
                    .white.opacity(0.62),
                    Color(red: 0.80, green: 0.86, blue: 0.95).opacity(0.22),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 3:
            return LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.78, blue: 0.58).opacity(0.52),
                    Color(red: 0.77, green: 0.47, blue: 0.27).opacity(0.2),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [.white.opacity(0.2), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var unitLabel: String {
        metric.unit(for: preferredMetric)
    }

    private var isCurrentUser: Bool {
        entry?.isCurrentUser == true
    }

    private var displayName: String {
        entry?.displayName ?? "Open Spot"
    }

    var body: some View {
        VStack(spacing: 10) {
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))
            }

            profileImage
                .frame(width: avatarSize, height: avatarSize)

            VStack(spacing: 2) {
                Text(displayName)
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(isCurrentUser ? .accent : (colorScheme == .dark ? .white : .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let entry {
                    Text(entry.formattedValue)
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)

                    if !unitLabel.isEmpty {
                        Text(unitLabel)
                            .font(.montserratRegular(size: 9))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.52) : .gray)
                    }
                } else {
                    Text("Waiting")
                        .font(.montserratRegular(size: 10))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .gray)
                }
            }
            .frame(maxWidth: .infinity)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(pedestalFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(pedestalStrokeColor, lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.62), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.1
                            )
                            .padding(0.5)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(pedestalShine)
                            .blendMode(.screen)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.26))
                            .frame(height: 5)
                            .blur(radius: 3)
                            .padding(.horizontal, 10)
                            .padding(.top, 5)
                    }

                Text("\(rank)")
                    .font(.montserratBold(size: rank == 1 ? 48 : 42))
                    .foregroundStyle(rankColor)
            }
            .frame(height: pedestalHeight)
        }
    }

    @ViewBuilder
    private var profileImage: some View {
        if let photoURL = entry?.photoURL {
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
            .overlay(
                Circle()
                    .stroke(medalRingGradient, lineWidth: rank == 1 ? 4 : 3)
            )
            .overlay {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.5),
                                .clear,
                                .white.opacity(0.28),
                                .clear,
                                .white.opacity(0.5)
                            ],
                            center: .center
                        ),
                        lineWidth: 1.2
                    )
                    .padding(1.5)
            }
            .shadow(color: medalRingGlow.opacity(colorScheme == .dark ? 0.62 : 0.34), radius: 8, x: 0, y: 2)
            .id(photoURL)
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(isCurrentUser ? Color.accent.opacity(0.24) : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15)))
            .overlay(
                Image(systemName: entry == nil ? "sparkles" : "person.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isCurrentUser ? .accent : (colorScheme == .dark ? .white.opacity(0.6) : .gray))
            )
            .overlay(
                Circle()
                    .stroke(medalRingGradient, lineWidth: rank == 1 ? 4 : 3)
            )
            .overlay {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.5),
                                .clear,
                                .white.opacity(0.28),
                                .clear,
                                .white.opacity(0.5)
                            ],
                            center: .center
                        ),
                        lineWidth: 1.2
                    )
                    .padding(1.5)
            }
            .shadow(color: medalRingGlow.opacity(colorScheme == .dark ? 0.54 : 0.3), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    LeaderboardPodiumView(
        entries: [
            LeaderboardEntry(userId: "1", displayName: "Luna Ramirez", rank: 1, value: 16086, formattedValue: "16,086", isCurrentUser: false),
            LeaderboardEntry(userId: "2", displayName: "Ethan Moore", rank: 2, value: 14064, formattedValue: "14,064", isCurrentUser: false)
        ],
        metric: .climb
    )
    .themedBackground()
}
