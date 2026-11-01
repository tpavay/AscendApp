import SwiftData
import SwiftUI

/// Where Save climb lands: what the climb did, before anything else.
///
/// A climb the pace check cleared shows where it put the climber on this week's steps board. One
/// it kept off the boards says so and says why, and never invents a standing. Every standing here
/// counts climbers on that board - the population is named in the line, because a rank beside an
/// unnamed number reads as a bigger field than it is.
struct LoggedClimbResultView: View {
    let workout: Workout
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationViewModel.self) private var authVM
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var standing = HomeDashboardViewModel()
    @State private var showingShareSheet = false

    private var primaryBestEffort: RankedBestEffort? {
        BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: [workout])
            .primaryEffort(for: workout)
    }

    private var countsOnLeaderboards: Bool {
        workout.leaderboardStatus == .eligible
    }

    /// The standing is this week's, so a climb dated before this week has none to report: the
    /// week it counted toward is closed and this one says nothing about it.
    private var standsInThisWeek: Bool {
        LeaderboardTimeFrame.weekly.contains(workout.date, referenceDate: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(workout.name)
                .font(.montserratBold(size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 18) {
                    standingSection
                    statsGrid
                    bestEffortCard
                    Text("Logged by hand")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            VStack(spacing: 6) {
                Button {
                    showingShareSheet = true
                } label: {
                    Text("SHARE")
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accent)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onDone) {
                    Text("DONE")
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheetView(workout: workout, climb: nil, climbRank: nil, climbRankTotal: nil)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: "0B0B0B"))
        }
        .task {
            guard countsOnLeaderboards, standsInThisWeek else { return }
            standing.refreshWeeklyRank(
                userId: authVM.user?.uid,
                displayName: authVM.displayName,
                photoURL: authVM.customProfilePictureURL ?? authVM.photoURL,
                modelContext: modelContext,
                forceRemote: true
            )
        }
        .trackOnce(screen: .loggedClimbResult)
    }

    // MARK: - Standing

    @ViewBuilder
    private var standingSection: some View {
        if countsOnLeaderboards {
            if !standsInThisWeek {
                EmptyView()
            } else if let rank = standing.weeklyRank, let population = standing.weeklyRankSummary?.population {
                VStack(spacing: 8) {
                    Text(rank.rankOrdinalText)
                        .font(.montserratBold(size: 76))
                        .foregroundStyle(Color.accent)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text("MOST STEPS OF \(population.formatted()) CLIMBERS THIS WEEK")
                        .font(.montserratBold(size: 10))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(rank.rankOrdinalText) in steps this week, of \(population.formatted()) climbers"
                )
            } else if standing.isRankLoading {
                ProgressView()
                    .tint(.white.opacity(0.6))
                    .frame(height: 96)
            }
        } else {
            offTheBoardsCard
        }
    }

    private var offTheBoardsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OFF THE LEADERBOARDS")
                .font(.montserratBold(size: 12))
                .tracking(1)
                .foregroundStyle(Color.ascendCaution)

            Text(
                LoggedClimbCopy.savedOffTheBoardsNote(
                    stepsPerMinute: workout.stepsPerMinute ?? 0
                )
            )
            .font(.montserratMedium(size: 13))
            .foregroundStyle(.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.ascendCaution.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.ascendCaution.opacity(0.4), lineWidth: 1)
                )
        )
        .accessibilityIdentifier("logged-climb-off-the-boards")
    }

    // MARK: - Stats

    private var statsGrid: some View {
        HStack(spacing: 10) {
            statCard(title: "TOTAL STEPS", value: (workout.recordedSteps ?? 0).formatted())
            statCard(title: "DURATION", value: workout.durationFormatted)
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.montserratBold(size: 9))
                .foregroundStyle(.white.opacity(0.42))

            Text(value)
                .font(.montserratBold(size: 22))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var bestEffortCard: some View {
        if let effort = primaryBestEffort {
            HStack(spacing: 14) {
                AppIcon(token: .bestEffortTrophy, pointSize: 22, weight: .semibold)
                    .foregroundStyle(effort.trophyColor)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text("BEST EFFORT")
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(Color.accent)

                    Text(effort.sentence)
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                if effort.origin != .live {
                    ClimbOriginMark(origin: effort.origin, pointSize: 12)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }
}
