import SwiftUI

struct LiveReplayLeaderboardPanel: View {
    @State private var selectedFilter: LiveReplayLeaderboardFilter = .everyone
    @State private var hasScrolledToInitialCurrentUser = false

    let rows: [ModeratedReplayLeaderboardRow]
    let progressScaleSteps: Int
    let targetStepGoal: Int?
    let progress: Double
    let currentUserPhotoURL: URL?
    /// Where the climber's previous best on this climb had reached at this
    /// moment, on the same step scale as `progressScaleSteps`, or nil when they
    /// have none. Drawn as the `BEST` marker inside their own row - never as a
    /// row of its own, and never counted. See `LiveReplayPreviousBestMarker`.
    var previousBestStepsAtBucket: Int?
    let fetchFailed: Bool
    /// What this board may state about where the climber stands - a leaderboard
    /// placing over the field it was measured against, or, where nobody else has
    /// finished, their placing among their own climbs. Never a bare ordinal.
    var standing: LiveReplayLiveStanding = .racing(field: nil, ownClimbs: nil)
    let tint: Color
    let effectiveColorScheme: ColorScheme
    var showsFilter: Bool = true

    private var visibleRows: [ModeratedReplayLeaderboardRow] {
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
                            resolvedRowView(for: row)
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

            standingFooter
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            if selectedFilter == .currentUser, visibleRows.isEmpty {
                selectedFilter = .everyone
            }
        }
    }

    /// What the board states beneath its rows.
    ///
    /// A live race collapses a rival's repeat runs to their best while the static
    /// per-climb board keeps every completion, so the two boards show different
    /// totals for one climb on purpose. Stating the population here is what keeps
    /// that from reading as a defect - and a board with no field it can
    /// substantiate states nothing, because the rows on screen are a window, not a
    /// count.
    ///
    /// Where nobody else has finished, there is no field to name and no
    /// leaderboard placing to state, so the climber's own climbs take the whole
    /// footer rather than a `1 CLIMBER` line sitting beside an unlabelled `#1`.
    @ViewBuilder
    private var standingFooter: some View {
        switch standing {
        case .racing(let field, let ownClimbs):
            if let field, field.count > 0 {
                LiveReplayFieldSizeLine(
                    field: field,
                    effectiveColorScheme: effectiveColorScheme
                )
            }

            if let ownClimbs {
                Text("\(ownClimbs.ordinalText.uppercased()) \(ownClimbs.fieldLabel)")
                    .font(.montserratBold(size: 10))
                    .tracking(1.1)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }

        case .alone(let ownClimbs):
            if let ownClimbs {
                LiveReplayOwnClimbsStanding(
                    placing: ownClimbs,
                    effectiveColorScheme: effectiveColorScheme
                )
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

    /// The anchor the board scrolls to: the attempt in progress, which is the
    /// only row that moves. A repeat climber also owns their earlier
    /// completions on this board, and anchoring on one of those would park the
    /// view somewhere the climber is not.
    private var currentUserRowID: String? {
        rows.first(where: \.isLiveAttempt)?.id
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

    @ViewBuilder
    private func resolvedRowView(
        for row: ModeratedReplayLeaderboardRow
    ) -> some View {
        if !row.isCurrentUser, row.userId != nil {
            NavigationLink {
                OtherUserProfileView(
                    identity: row.identity,
                    moderationSource: .liveReplay
                )
            } label: {
                rowView(row)
            }
            .buttonStyle(.plain)
        } else {
            rowView(row)
        }
    }

    private func rowView(_ row: ModeratedReplayLeaderboardRow) -> some View {
        LiveReplayLeaderboardRowView(
            row: row,
            progressScaleSteps: progressScaleSteps,
            progress: progress,
            previousBestProgress: row.isCurrentUser ? previousBestProgress : nil,
            currentUserPhotoURL: currentUserPhotoURL,
            showsLeaderboardRank: standing.showsLeaderboardRank,
            tint: tint,
            effectiveColorScheme: effectiveColorScheme
        )
    }

    /// The previous best's position on the row's own progress scale, or nil when
    /// there is nothing to mark.
    private var previousBestProgress: Double? {
        guard let previousBestStepsAtBucket,
              previousBestStepsAtBucket > 0,
              progressScaleSteps > 0 else {
            return nil
        }

        return min(Double(previousBestStepsAtBucket) / Double(progressScaleSteps), 1)
    }

}

/// The whole footer for a board nobody else has finished.
///
/// It states the one placing that board can substantiate - where this run sits
/// among the climber's own climbs - in the finish card's idiom: the accent
/// ordinal over the population it counted. No leaderboard ordinal is drawn
/// anywhere on such a board, so this is never a second number beside one.
private struct LiveReplayOwnClimbsStanding: View {
    let placing: LiveReplayPersonalPlacing
    let effectiveColorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 2) {
            Text(placing.ordinalText.uppercased())
                .font(.montserratBold(size: 22))
                .foregroundStyle(Color.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(placing.fieldLabel)
                .font(.montserratBold(size: 10))
                .tracking(1.1)
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(hairlineColor)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var secondaryColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.52) : .black.opacity(0.48)
    }

    private var hairlineColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }
}

private struct LiveReplayLeaderboardRowView: View {
    let row: ModeratedReplayLeaderboardRow
    let progressScaleSteps: Int
    let progress: Double
    let previousBestProgress: Double?
    let currentUserPhotoURL: URL?
    /// False on a board nobody else has finished, where no leaderboard placing
    /// exists to draw.
    let showsLeaderboardRank: Bool
    let tint: Color
    let effectiveColorScheme: ColorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            if row.isLiveAttempt {
                progressBackground
            }

            HStack(spacing: 10) {
                Group {
                    if let rankLabel {
                        Text(rankLabel)
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(row.isLiveAttempt ? tint : secondaryColor)
                            .monospacedDigit()
                    }
                }
                .frame(width: 38, alignment: .center)

                avatarView

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(row.identity.displayName)
                            .font(.montserratBold(size: 17))
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

                    // A rival's row is worth characterising; the viewer's is
                    // not. The attempt in progress can never carry demographics
                    // - it is assembled from the live step count - so drawing
                    // them under the climber's own finished attempt is what let
                    // two rows belonging to one person disagree about whose
                    // they were.
                    if !row.isCurrentUser,
                       let demographicSummaryText = row.demographicSummaryText {
                        Text(demographicSummaryText)
                            .font(.montserratSemiBold(size: 10))
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                Spacer(minLength: 0)

                Text(row.stepsAtBucket.formatted())
                    .font(.montserratBold(size: row.isLiveAttempt ? 24 : 22))
                    .foregroundStyle(row.isLiveAttempt ? tint : primaryColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
            .padding(.trailing, 4)

            previousBestMarker
        }
        .frame(height: row.isLiveAttempt ? 74 : 70)
        .accessibilityElement(children: .combine)
    }

    /// The climber's previous best, drawn over their own row rather than beside
    /// it. Drawn last so the line stays legible across the avatar and the name;
    /// the word gets out of the trailing number's way on its own.
    @ViewBuilder
    private var previousBestMarker: some View {
        if let previousBestProgress {
            LiveReplayPreviousBestMarker(
                progress: previousBestProgress,
                lineColor: primaryColor
            )
        }
    }

    private var rankLabel: String {
        row.rank.map(String.init) ?? "--"
    /// The viewer's own earlier completion holds no placing, so its cell draws
    /// nothing at all, and neither does any row on a board with no leaderboard
    /// placing to state. `--` still stands for a rank that could not be
    /// resolved, which is a different statement and has to keep reading as one.
    private var rankLabel: String? {
        guard showsLeaderboardRank, !row.isViewerGhost else { return nil }
        return row.rank.map(String.init) ?? "--"
    }

    private var rowProgress: Double {
        if row.isLiveAttempt {
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
        row.isCurrentUser ?
            (row.identity.photoURL ?? currentUserPhotoURL) :
            row.identity.photoURL
    }

    @ViewBuilder
    private var avatarTokenView: some View {
        Group {
            if row.identity.avatarToken.isEmpty {
                Image(systemName: PublicClimberIdentity.genericAvatarSystemName)
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
            } else {
                Text(row.identity.avatarToken)
                    .font(.montserratBold(size: 13))
            }
        }
            .foregroundStyle(row.isCurrentUser ? .black : .white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(row.isCurrentUser ? tint : avatarColor))
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
