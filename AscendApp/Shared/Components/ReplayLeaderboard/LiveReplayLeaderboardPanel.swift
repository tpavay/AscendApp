import SwiftUI

struct LiveReplayLeaderboardPanel: View {
    @State private var selectedFilter: LiveReplayLeaderboardFilter = .everyone
    @State private var hasScrolledToInitialCurrentUser = false

    let rows: [LiveReplayLeaderboardRow]
    let progressScaleSteps: Int
    let targetStepGoal: Int?
    let progress: Double
    let currentUserPhotoURL: URL?
    let fetchFailed: Bool
    let tint: Color
    let effectiveColorScheme: ColorScheme
    var showsFilter: Bool = true

    private var visibleRows: [LiveReplayLeaderboardRow] {
        switch selectedFilter {
        case .everyone:
            return rows
        case .currentUser:
            return rows.filter(\.isCurrentUser)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LEADERBOARD")
                    .font(.montserratBold(size: 14))
                    .tracking(1.1)
                    .foregroundStyle(primaryColor)

                Spacer(minLength: 0)

                headerTrailingMetric
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            if showsFilter {
                filterControl
                    .padding(.bottom, 12)
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleRows) { row in
                            LiveReplayLeaderboardRowView(
                                row: row,
                                progressScaleSteps: progressScaleSteps,
                                progress: progress,
                                currentUserPhotoURL: currentUserPhotoURL,
                                tint: tint,
                                effectiveColorScheme: effectiveColorScheme
                            )
                            .id(row.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToCurrentUserIfNeeded(using: proxy)
                }
                .onChange(of: currentUserRowID) { _, _ in
                    scrollToCurrentUserIfNeeded(using: proxy)
                }
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.82),
                    value: visibleRows.map(\.id)
                )
            }

            if fetchFailed && rows.count <= 1 {
                Text("Leaderboard unavailable")
                    .font(.montserratSemiBold(size: 11))
                    .foregroundStyle(secondaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            if selectedFilter == .currentUser, visibleRows.isEmpty {
                selectedFilter = .everyone
            }
        }
    }

    @ViewBuilder
    private var headerTrailingMetric: some View {
        if let targetStepGoal {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(targetStepGoal.formatted())
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(primaryColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("STEPS")
                    .font(.montserratBold(size: 13))
                    .tracking(0.8)
                    .foregroundStyle(secondaryColor)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("OPEN")
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(primaryColor)

                Text("CLIMB")
                    .font(.montserratBold(size: 11))
                    .tracking(0.8)
                    .foregroundStyle(secondaryColor)
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
                                .fill(selectedFilter == filter ? tint : .white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .disabled(filter == .currentUser && currentUserRowID == nil)
                .opacity(filter == .currentUser && currentUserRowID == nil ? 0.42 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var primaryColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.42) : .black.opacity(0.4)
    }

    private var currentUserRowID: String? {
        rows.first(where: \.isCurrentUser)?.id
    }

    private func scrollToCurrentUserIfNeeded(using proxy: ScrollViewProxy) {
        guard !hasScrolledToInitialCurrentUser,
              let currentUserRowID else {
            return
        }

        hasScrolledToInitialCurrentUser = true

        Task {
            await Task.yield()
            withAnimation(.easeOut(duration: 0.24)) {
                proxy.scrollTo(currentUserRowID, anchor: .center)
            }
        }
    }
}

private struct LiveReplayLeaderboardRowView: View {
    let row: LiveReplayLeaderboardRow
    let progressScaleSteps: Int
    let progress: Double
    let currentUserPhotoURL: URL?
    let tint: Color
    let effectiveColorScheme: ColorScheme

    private var identity: PublicClimberIdentity.Presentation {
        row.publicIdentity(currentUserPhotoURL: currentUserPhotoURL)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if row.isCurrentUser {
                progressBackground
            }

            HStack(spacing: 10) {
                Text(rankLabel)
                    .font(.montserratBold(size: 16))
                    .foregroundStyle(row.isCurrentUser ? tint : secondaryColor)
                    .frame(width: 38, alignment: .center)
                    .monospacedDigit()

                avatarView

                VStack(alignment: .leading, spacing: 3) {
                    Text(identity.displayName)
                        .font(.montserratBold(size: 17))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if let demographicSummaryText = row.demographicSummaryText {
                        Text(demographicSummaryText)
                            .font(.montserratSemiBold(size: 10))
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                Spacer(minLength: 0)

                Text(row.stepsAtBucket.formatted())
                    .font(.montserratBold(size: row.isCurrentUser ? 24 : 22))
                    .foregroundStyle(row.isCurrentUser ? tint : primaryColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
            .padding(.trailing, 4)
        }
        .frame(height: row.isCurrentUser ? 74 : 70)
        .accessibilityElement(children: .combine)
    }

    private var rankLabel: String {
        row.rank.map(String.init) ?? "--"
    }

    private var rowProgress: Double {
        if row.isCurrentUser {
            return min(max(progress, 0), 1)
        }

        guard progressScaleSteps > 0 else { return 0 }
        return min(max(Double(row.stepsAtBucket) / Double(progressScaleSteps), 0), 1)
    }

    private var progressBackground: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(tint.opacity(effectiveColorScheme == .dark ? 0.12 : 0.14))

                Rectangle()
                    .fill(tint.opacity(effectiveColorScheme == .dark ? 0.34 : 0.24))
                    .frame(width: width * rowProgress)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: rowProgress)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let photoURL = resolvedPhotoURL {
            AsyncImage(
                url: photoURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.2))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    avatarTokenView
                @unknown default:
                    avatarTokenView
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.10), lineWidth: 1)
            )
            .id(photoURL)
        } else {
            avatarTokenView
        }
    }

    private var resolvedPhotoURL: URL? {
        identity.photoURL
    }

    @ViewBuilder
    private var avatarTokenView: some View {
        if identity.usesGenericAvatar {
            Image(systemName: PublicClimberIdentity.genericAvatarSystemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(row.isCurrentUser ? .black : secondaryColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(row.isCurrentUser ? tint : avatarColor.opacity(0.28)))
        } else {
            Text(identity.avatarToken)
                .font(.montserratBold(size: 13))
                .foregroundStyle(row.isCurrentUser ? .black : .white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(row.isCurrentUser ? tint : avatarColor))
        }
    }

    private var primaryColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.34) : .black.opacity(0.34)
    }

    private var avatarColor: Color {
        let colors: [Color] = [
            Color(hex: "8C5A36"),
            Color(hex: "C69475"),
            Color(hex: "6E4E33"),
            Color(hex: "A36A42")
        ]
        return colors[Int(row.id.hashValue.magnitude % UInt(colors.count))]
    }
}
