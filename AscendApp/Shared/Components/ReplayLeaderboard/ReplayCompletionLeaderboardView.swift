import SwiftUI

struct ReplayCompletionLeaderboardView: View {
    @State private var selectedFilter: LiveReplayLeaderboardFilter = .everyone

    let rows: [LiveReplayLeaderboardRow]
    let completedCount: Int
    let isLoading: Bool
    let fetchFailed: Bool
    let currentUserPhotoURL: URL?
    let effectiveColorScheme: ColorScheme
    let emptyTitle: String
    let emptyMessage: String

    private var visibleRows: [LiveReplayLeaderboardRow] {
        switch selectedFilter {
        case .everyone:
            return rows
        case .currentUser:
            return rows.filter(\.isCurrentUser)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            completionCountRow

            if !rows.isEmpty {
                filterControl
            }

            if isLoading && rows.isEmpty {
                loadingState
            } else if !visibleRows.isEmpty {
                VStack(spacing: 8) {
                    ForEach(visibleRows) { row in
                        ReplayCompletionLeaderboardRowView(
                            row: row,
                            currentUserPhotoURL: currentUserPhotoURL,
                            effectiveColorScheme: effectiveColorScheme
                        )
                    }
                }
            } else {
                emptyState
            }

            if fetchFailed && !isLoading {
                Text("Leaderboard unavailable")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(Color.red.opacity(0.82))
            }
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            if selectedFilter == .currentUser, currentUserRowID == nil {
                selectedFilter = .everyone
            }
        }
    }

    @ViewBuilder
    private var completionCountRow: some View {
        if completedCount > 0 {
            HStack(alignment: .firstTextBaseline) {
                Spacer(minLength: 0)
                Text("\(completedCount.formatted()) completed")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.accent)
                    .monospacedDigit()
            }
        }
    }

    private var filterControl: some View {
        HStack(spacing: 8) {
            ForEach(LiveReplayLeaderboardFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(selectedFilter == filter ? .black : secondaryColor)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? Color.accent : .white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .disabled(filter == .currentUser && currentUserRowID == nil)
                .opacity(filter == .currentUser && currentUserRowID == nil ? 0.42 : 1)
            }

            Spacer(minLength: 0)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.accent)

            Text("Loading leaderboard")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(secondaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyTitle)
                .font(.montserratBold(size: 18))
                .foregroundStyle(primaryColor)

            Text(emptyMessage)
                .font(.montserratRegular(size: 14))
                .foregroundStyle(secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }

    private var currentUserRowID: String? {
        rows.first(where: \.isCurrentUser)?.id
    }

    private var primaryColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.5)
    }
}

private struct ReplayCompletionLeaderboardRowView: View {
    let row: LiveReplayLeaderboardRow
    let currentUserPhotoURL: URL?
    let effectiveColorScheme: ColorScheme

    var body: some View {
        let rank = row.rank
        let isPodium = isPodiumRank(rank)
        let rowAccent = leaderboardAccentColor(for: rank)

        HStack(alignment: .center, spacing: rank == 1 ? 14 : 12) {
            rankView(for: rank)

            avatarView(
                size: rank == 1 ? 50 : 42,
                borderColor: isPodium ? rowAccent : nil
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(row.isCurrentUser ? "You" : row.displayName)
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if row.isCurrentUser {
                        Text("YOU")
                            .font(.montserratBold(size: 9))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accent)
                            )
                    }
                }

                Text("\(displaySteps.formatted()) steps")
                    .font(.montserratMedium(size: rank == 1 ? 12 : 11))
                    .foregroundStyle(secondaryColor)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(durationText)
                    .font(.montserratBold(size: rank == 1 ? 18 : 16))
                    .foregroundStyle(isPodium ? rowAccent : (row.isCurrentUser ? .accent : primaryColor))
                    .monospacedDigit()

                if let averageStepsPerMinute = row.averageStepsPerMinute {
                    Text("\(Int(averageStepsPerMinute.rounded()).formatted()) avg SPM")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(secondaryColor)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, rank == 1 ? 16 : 13)
        .padding(.horizontal, isPodium || row.isCurrentUser ? 12 : 0)
        .background { rowBackground(for: row) }
        .overlay(alignment: .bottom) {
            if !isPodium && !row.isCurrentUser {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .shadow(
            color: rank == 1 ? rowAccent.opacity(effectiveColorScheme == .dark ? 0.22 : 0.12) : .clear,
            radius: rank == 1 ? 12 : 0,
            x: 0,
            y: rank == 1 ? 4 : 0
        )
        .accessibilityElement(children: .combine)
    }

    private var displaySteps: Int {
        max(row.finalSteps, row.stepsAtBucket)
    }

    private var durationText: String {
        guard let completionDurationSeconds = row.completionDurationSeconds else {
            return "--"
        }

        return DurationFormatter.format(duration: completionDurationSeconds)
    }

    @ViewBuilder
    private func rankView(for rank: Int?) -> some View {
        if rank == 1 {
            Image(systemName: "crown.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(leaderboardGold)
                .frame(width: 34, alignment: .leading)
                .accessibilityLabel("Rank 1")
        } else {
            Text("#\(rank?.formatted() ?? "--")")
                .font(.montserratBold(size: 15))
                .foregroundStyle(leaderboardAccentColor(for: rank))
                .frame(width: 34, alignment: .leading)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func avatarView(size: CGFloat, borderColor: Color?) -> some View {
        let resolvedBorderColor = borderColor ?? (row.isCurrentUser ? Color.accent : .white.opacity(0.14))

        if let photoURL = row.isCurrentUser ? (row.photoURL ?? currentUserPhotoURL) : row.photoURL {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    avatarToken(size: size, borderColor: resolvedBorderColor)
                @unknown default:
                    avatarToken(size: size, borderColor: resolvedBorderColor)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(resolvedBorderColor, lineWidth: row.isCurrentUser || borderColor != nil ? 2 : 1)
            )
            .id(photoURL)
        } else {
            avatarToken(size: size, borderColor: resolvedBorderColor)
        }
    }

    private func avatarToken(size: CGFloat, borderColor: Color?) -> some View {
        Text(row.isCurrentUser ? "YOU" : row.avatarToken)
            .font(.montserratBold(size: row.isCurrentUser ? 11 : 13))
            .foregroundStyle(row.isCurrentUser ? .black : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(row.isCurrentUser ? Color.accent : avatarBackgroundColor)
            )
            .overlay(
                Circle()
                    .stroke(borderColor ?? (row.isCurrentUser ? Color.accent.opacity(0.7) : .white.opacity(0.14)), lineWidth: borderColor == nil ? 1 : 2)
            )
    }

    @ViewBuilder
    private func rowBackground(for row: LiveReplayLeaderboardRow) -> some View {
        let rank = row.rank
        let rowAccent = leaderboardAccentColor(for: rank)

        if rank == 1 {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            rowAccent.opacity(effectiveColorScheme == .dark ? 0.18 : 0.12),
                            rowAccent.opacity(effectiveColorScheme == .dark ? 0.07 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(rowAccent.opacity(0.72), lineWidth: 1.4)
                )
        } else if isPodiumRank(rank) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rowAccent.opacity(effectiveColorScheme == .dark ? 0.10 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(rowAccent.opacity(0.28), lineWidth: 1)
                )
        } else if row.isCurrentUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accent.opacity(effectiveColorScheme == .dark ? 0.12 : 0.10))
        }
    }

    private var avatarBackgroundColor: Color {
        let colors: [Color] = [
            Color(red: 0.94, green: 0.33, blue: 0.43),
            Color(red: 0.21, green: 0.72, blue: 0.69),
            Color(red: 1.0, green: 0.57, blue: 0.08),
            Color(red: 0.40, green: 0.34, blue: 0.86)
        ]
        return colors[Int(row.id.hashValue.magnitude % UInt(colors.count))]
    }

    private func isPodiumRank(_ rank: Int?) -> Bool {
        guard let rank else { return false }
        return (1...3).contains(rank)
    }

    private func leaderboardAccentColor(for rank: Int?) -> Color {
        switch rank {
        case 1:
            return leaderboardGold
        case 2:
            return Color(hex: "BFC4CC")
        case 3:
            return Color(hex: "C8793D")
        default:
            return Color.customGray
        }
    }

    private var leaderboardGold: Color {
        Color(hex: "F3D76B")
    }

    private var primaryColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48)
    }
}
