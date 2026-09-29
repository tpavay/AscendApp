import Foundation
import Observation
import SwiftData

/// Decides whether the recap shows on this open, and marks it seen when it closes.
///
/// It only ever runs from the main app, so the recap can never cover the update lockout,
/// sign-in, the paywall or onboarding; the caller also holds it back when the open was
/// a push, a deep link, or a Live Climb resume. Seen is recorded twice: `seenAt` on the
/// server, so no device shows a recap twice, and a local marker, so an offline open whose
/// write has not landed yet does not show it again on the next launch.
@MainActor
@Observable
final class PeriodRecapCoordinator {
    static let shared = PeriodRecapCoordinator()

    /// How many unseen recaps one read considers - enough for four weeks and two months.
    static let fetchLimit = 10

    /// The story on screen, if any.
    private(set) var story: PeriodRecapStory?
    /// Whether the story actually reached the screen. A cover SwiftUI never put up (another
    /// presentation won) is taken back on the next evaluation instead of blocking every open.
    @ObservationIgnored private var isStoryOnScreen = false

    @ObservationIgnored private let recaps: any PeriodRecapReading
    @ObservationIgnored private let results: any LeaderboardResultsReading
    @ObservationIgnored private let seenStore: PeriodRecapLocalSeenStore
    @ObservationIgnored private let isFeatureEnabled: () -> Bool
    @ObservationIgnored private var isEvaluating = false
    @ObservationIgnored private var activeUserId: String?

    init(
        recaps: any PeriodRecapReading = PeriodRecapRepository.shared,
        results: any LeaderboardResultsReading = LeaderboardResultsRepository.shared,
        seenStore: PeriodRecapLocalSeenStore = PeriodRecapLocalSeenStore(),
        isFeatureEnabled: @escaping () -> Bool = {
            RemoteFeatureFlagStore.shared.isEnabled(.periodRecap)
        }
    ) {
        self.recaps = recaps
        self.results = results
        self.seenStore = seenStore
        self.isFeatureEnabled = isFeatureEnabled
    }

    /// Reads the climber's unseen recaps and, when there is a story to tell, presents it.
    ///
    /// `isEligible` is asked again after the reads, immediately before presenting: a Live
    /// Climb, a routed open or the update nudge that arrived while they were in flight wins,
    /// and the recap waits, unseen, for the next open.
    func evaluate(
        userId: String,
        modelContext: ModelContext?,
        now: Date = .now,
        isEligible: @MainActor () -> Bool = { true }
    ) async {
        if story != nil, !isStoryOnScreen {
            story = nil
        }
        guard story == nil, !isEvaluating, isFeatureEnabled() else { return }
        isEvaluating = true
        activeUserId = userId
        defer { isEvaluating = false }

        do {
            let fetched = try await recaps.fetchUnseen(userId: userId, limit: Self.fetchLimit)
            let locallySeen = seenStore.seenIDs(userId: userId)
            // A recap this device already showed, whose seenAt write never reached the
            // server, is re-sent rather than re-shown - and so is the backlog older than it.
            let pendingWrites = fetched.filter { locallySeen.contains($0.id) }
            let shownThrough = pendingWrites.compactMap(\.period.endAt).max()
            if let shownThrough {
                try? await markSeenOnServer(userId: userId, recapIDs: pendingWrites.map(\.id))
                try? await markBacklogSeenOnServer(userId: userId, endingOnOrBefore: shownThrough)
            }
            let unseen = fetched.filter { recap in
                !locallySeen.contains(recap.id)
                    && (recap.period.endAt ?? .distantFuture) > (shownThrough ?? .distantPast)
            }
            guard !unseen.isEmpty else { return }

            let bundles = await loadResults(for: unseen)
            let bestEfforts = modelContext.map {
                PeriodRecapBestEffortFinder.bestEfforts(in: unseen.map(\.period), modelContext: $0)
            } ?? [:]

            guard activeUserId == userId,
                  let story = PeriodRecapStoryBuilder.build(
                    recaps: unseen,
                    results: bundles,
                    bestEfforts: bestEfforts,
                    viewerId: userId,
                    now: now
                  ),
                  isEligible() else { return }
            isStoryOnScreen = false
            self.story = story
        } catch {
            AppDiagnosticsRecorder.shared.record(
                "period_recap_load_failed",
                level: .warning,
                details: ["error_type": String(describing: type(of: error))]
            )
        }
    }

    /// The story's cover is on screen, so closing it from here on counts as seen.
    func storyDidAppear() {
        isStoryOnScreen = story != nil
    }

    /// Closing the story - by finishing it, tapping through, or dismissing it - counts as seen,
    /// along with every older unseen recap, so a long absence never produces a second catch-up.
    func dismiss() {
        isStoryOnScreen = false
        guard let story, let userId = activeUserId else {
            self.story = nil
            return
        }
        self.story = nil
        seenStore.markSeen(userId: userId, recapIDs: story.recapIDs)
        Task {
            try? await markSeenOnServer(userId: userId, recapIDs: story.recapIDs)
            if let coveredFrom = story.oldestPeriodEndAt {
                try? await markBacklogSeenOnServer(userId: userId, endingOnOrBefore: coveredFrom)
            }
        }
    }

    /// Signing out drops the story on screen; the local markers stay with their account.
    func clear() {
        story = nil
        activeUserId = nil
    }

    /// Presents a story directly - for evidence tests and the debug preview.
    func present(_ story: PeriodRecapStory, userId: String) {
        activeUserId = userId
        isStoryOnScreen = false
        self.story = story
    }

    private func markSeenOnServer(userId: String, recapIDs: [String]) async throws {
        guard RemoteFeatureGate.allows(.periodRecap, path: "PeriodRecapCoordinator.markSeen") else {
            return
        }
        try await recaps.markSeen(userId: userId, recapIDs: recapIDs)
    }

    private func markBacklogSeenOnServer(userId: String, endingOnOrBefore cutoff: Date) async throws {
        guard RemoteFeatureGate.allows(.periodRecap, path: "PeriodRecapCoordinator.markBacklogSeen") else {
            return
        }
        try await recaps.markUnseenSeen(userId: userId, endingOnOrBefore: cutoff)
    }

    /// Reads the results for the periods the story will show. A result that cannot be read
    /// only costs that period its crown; the climber's own recap still shows.
    private func loadResults(for unseen: [PeriodRecap]) async -> [String: PeriodRecapResultBundle] {
        let wanted = Set(PeriodRecapStoryBuilder.resultIDs(for: unseen))
        let periods = unseen.filter { wanted.contains($0.resultID) }.map(\.period)
        let results = results

        return await withTaskGroup(of: PeriodRecapResultBundle?.self) { group in
            for period in periods {
                group.addTask {
                    do {
                        guard let result = try await results.fetchResult(
                            timeFrame: period.timeFrame,
                            periodKey: period.key
                        ) else { return nil }
                        let named = result.championUserIds + result.podiumUserIds + (result.mostClimbs?.userIds ?? [])
                        let placings = try await results.fetchPlacings(resultID: result.id, userIds: named)
                        return PeriodRecapResultBundle(result: result, placings: placings)
                    } catch {
                        AppDiagnosticsRecorder.shared.record(
                            "period_recap_result_load_failed",
                            level: .warning,
                            details: [
                                "period_key": period.key,
                                "error_type": String(describing: type(of: error))
                            ]
                        )
                        return nil
                    }
                }
            }
            var bundles: [String: PeriodRecapResultBundle] = [:]
            for await bundle in group {
                if let bundle { bundles[bundle.result.id] = bundle }
            }
            return bundles
        }
    }
}
