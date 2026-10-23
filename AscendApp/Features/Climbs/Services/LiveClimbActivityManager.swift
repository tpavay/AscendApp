@preconcurrency import ActivityKit
import FirebaseStorage
import Foundation

/// How long a published Live Activity state stays believable without a newer one.
///
/// Every update used to publish `staleDate: nil`, so when the process died the Lock Screen kept
/// showing the last steps and clock indefinitely - "66 steps, 1:02" for twenty minutes on
/// 2026-10-23, with nothing to tell the climber that nothing was counting. Fifteen seconds is
/// several update intervals past the per-second cadence, so a healthy session never goes stale and
/// a dead one is marked within the time it takes to notice the clock has stopped.
enum LiveClimbActivityStalenessPolicy {
    static let staleAfter: TimeInterval = 15

    static func staleDate(publishedAt: Date) -> Date {
        publishedAt.addingTimeInterval(staleAfter)
    }
}

@MainActor
final class LiveClimbActivityManager {
    static let shared = LiveClimbActivityManager()

    private var activity: Activity<LiveClimbActivityAttributes>?
    private var currentAttributes: LiveClimbActivityAttributes?
    private var lastState: LiveClimbActivityAttributes.ContentState?
    private var lastUpdateAt: Date?
    /// The stale date of the last content published, for the tests that hold the Lock Screen
    /// honest: a state with no stale date is a state that can lie forever.
    private(set) var lastPublishedStaleDate: Date?

    private init() {}

    /// Every live update travels with a stale date; only an end state publishes without one, since
    /// an ended activity is already the truth.
    func makeLiveContent(
        state: LiveClimbActivityAttributes.ContentState,
        now: Date = Date()
    ) -> ActivityContent<LiveClimbActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: LiveClimbActivityStalenessPolicy.staleDate(publishedAt: now)
        )
    }

    func start(
        climb: Climb,
        sessionID: String,
        steps: Int,
        rank: Int?,
        rankTotal: Int,
        standing: LiveReplayLiveStanding,
        duration: TimeInterval,
        progress: Double
    ) async {
        await start(
            climb: climb,
            sessionID: sessionID,
            sessionTitle: climb.name,
            sessionSubtitle: climb.displayLocation,
            targetSteps: climb.referenceStepCount,
            steps: steps,
            rank: rank,
            rankTotal: rankTotal,
            standing: standing,
            duration: duration,
            progress: progress
        )
    }

    func start(
        climb: Climb?,
        sessionID: String,
        sessionTitle: String,
        sessionSubtitle: String,
        targetSteps: Int,
        steps: Int,
        rank: Int?,
        rankTotal: Int,
        standing: LiveReplayLiveStanding,
        duration: TimeInterval,
        progress: Double
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        await endExistingActivities()

        let attributes = LiveClimbActivityAttributes(
            sessionID: sessionID,
            climbID: climb?.id ?? "just-climb",
            climbName: sessionTitle,
            climbLocation: sessionSubtitle,
            targetSteps: max(targetSteps, 0)
        )
        let state = makeState(
            steps: steps,
            rank: rank,
            rankTotal: rankTotal,
            standing: standing,
            duration: duration,
            progress: progress,
            status: .recording,
            photoURLString: nil
        )

        do {
            let content = makeLiveContent(state: state)
            let activity = try Activity<LiveClimbActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.activity = activity
            currentAttributes = attributes
            lastState = state
            lastUpdateAt = Date()
            lastPublishedStaleDate = content.staleDate
        } catch {
#if DEBUG
            debugLog("Live Climb Live Activity start failed: \(error.localizedDescription)")
#endif
            return
        }

        if let climb {
            let photoRequest = LiveClimbActivityPhotoRequest(
                climbID: climb.id,
                imageSetVersion: climb.imageSetVersion
            )
            Task {
                let photoURLString = await Self.resolvePhotoURLString(for: photoRequest)
                await self.setPhotoURLString(photoURLString, sessionID: attributes.sessionID)
            }
        }
    }

    func update(
        steps: Int,
        rank: Int?,
        rankTotal: Int,
        standing: LiveReplayLiveStanding,
        duration: TimeInterval,
        progress: Double,
        status: LiveClimbActivityStatus? = nil,
        force: Bool = false
    ) async {
        guard let activity else { return }

        let resolvedStatus = status ?? .recording
        let state = makeState(
            steps: steps,
            rank: rank,
            rankTotal: rankTotal,
            standing: standing,
            duration: duration,
            progress: progress,
            status: resolvedStatus,
            photoURLString: lastState?.climbPhotoURLString
        )

        guard force || shouldPublish(state) else { return }

        let content = makeLiveContent(state: state)
        await activity.update(content)
        lastState = state
        lastUpdateAt = Date()
        lastPublishedStaleDate = content.staleDate
    }

    func end(status: LiveClimbActivityStatus = .ended) async {
        let finalState = lastState.map {
            LiveClimbActivityAttributes.ContentState(
                steps: $0.steps,
                rank: $0.rank,
                rankTotal: $0.rankTotal,
                ownClimbs: $0.ownClimbs,
                board: $0.board,
                durationSeconds: $0.durationSeconds,
                progress: $0.progress,
                status: status,
                climbPhotoURLString: $0.climbPhotoURLString,
                updatedAt: Date()
            )
        }

        if let activity, let finalState {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        } else {
            await endExistingActivities()
        }

        activity = nil
        currentAttributes = nil
        lastState = nil
        lastUpdateAt = nil
        lastPublishedStaleDate = nil
    }

    func end(sessionID: String, status: LiveClimbActivityStatus = .ended) async {
        if currentAttributes?.sessionID == sessionID {
            await end(status: status)
            return
        }

        guard let activity = Activity<LiveClimbActivityAttributes>.activities.first(where: {
            $0.attributes.sessionID == sessionID
        }) else {
            return
        }

        let state = activity.content.state
        let finalState = LiveClimbActivityAttributes.ContentState(
            steps: state.steps,
            rank: state.rank,
            rankTotal: state.rankTotal,
            ownClimbs: state.ownClimbs,
            board: state.board,
            durationSeconds: state.durationSeconds,
            progress: state.progress,
            status: status,
            climbPhotoURLString: state.climbPhotoURLString,
            updatedAt: Date()
        )

        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
    }

    private func setPhotoURLString(_ photoURLString: String?, sessionID: String) async {
        guard currentAttributes?.sessionID == sessionID,
              let activity,
              let lastState else {
            return
        }

        let state = LiveClimbActivityAttributes.ContentState(
            steps: lastState.steps,
            rank: lastState.rank,
            rankTotal: lastState.rankTotal,
            ownClimbs: lastState.ownClimbs,
            board: lastState.board,
            durationSeconds: lastState.durationSeconds,
            progress: lastState.progress,
            status: lastState.status,
            climbPhotoURLString: photoURLString,
            updatedAt: Date()
        )

        let content = makeLiveContent(state: state)
        await activity.update(content)
        self.lastState = state
        lastUpdateAt = Date()
        lastPublishedStaleDate = content.staleDate
    }

    private func shouldPublish(_ state: LiveClimbActivityAttributes.ContentState) -> Bool {
        guard let lastState else { return true }

        if state.steps != lastState.steps ||
            state.rank != lastState.rank ||
            state.rankTotal != lastState.rankTotal ||
            state.ownClimbs != lastState.ownClimbs ||
            state.board != lastState.board ||
            state.status != lastState.status ||
            state.climbPhotoURLString != lastState.climbPhotoURLString {
            return true
        }

        if abs(state.durationSeconds - lastState.durationSeconds) >= 1 {
            return true
        }

        guard let lastUpdateAt else { return true }
        return Date().timeIntervalSince(lastUpdateAt) >= 1
    }

    private func makeState(
        steps: Int,
        rank: Int?,
        rankTotal: Int,
        standing: LiveReplayLiveStanding,
        duration: TimeInterval,
        progress: Double,
        status: LiveClimbActivityStatus,
        photoURLString: String?
    ) -> LiveClimbActivityAttributes.ContentState {
        let standingText = LiveClimbStandingText(rank: rank, rankTotal: rankTotal, standing: standing)
        return LiveClimbActivityAttributes.ContentState(
            steps: max(steps, 0),
            rank: standingText.rank,
            rankTotal: standingText.rankTotal,
            ownClimbs: standingText.ownClimbs,
            board: standingText.board,
            durationSeconds: max(Int(duration.rounded(.down)), 0),
            progress: min(max(progress, 0), 1),
            status: status,
            climbPhotoURLString: photoURLString,
            updatedAt: Date()
        )
    }

    private func endExistingActivities() async {
        for activity in Activity<LiveClimbActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func resolvePhotoURLString(for request: LiveClimbActivityPhotoRequest) async -> String? {
        for remotePath in request.candidateRemotePaths {
            do {
                let url = try await Storage.storage()
                    .reference(withPath: "climb-images/\(remotePath)")
                    .downloadURL()
                return url.absoluteString
            } catch {
                continue
            }
        }

        return nil
    }
}

private struct LiveClimbActivityPhotoRequest: Sendable {
    let climbID: String
    let imageSetVersion: Int

    var candidateRemotePaths: [String] {
        [
            "\(climbID)/v\(imageSetVersion)/card.heic",
            "\(climbID)/v\(imageSetVersion)/hero.heic",
            "\(climbID)/v\(imageSetVersion)/thumb.heic",
            "\(climbID)/card.heic",
            "\(climbID)/hero.heic",
            "\(climbID)/thumb.heic"
        ]
    }
}

extension LiveClimbStandingText {
    /// The standing a live session settled, as every live surface words it: a leaderboard
    /// placing only where there is a field to place against, and the climber's own climbs
    /// alongside it.
    init(rank: Int?, rankTotal: Int, standing: LiveReplayLiveStanding) {
        self.init(
            rank: standing.showsLeaderboardRank ? rank : nil,
            rankTotal: max(rankTotal, 0),
            ownClimbs: standing.ownClimbs.map { .init(placing: $0.placing, total: $0.total) },
            board: standing.showsLeaderboardRank ? .racing : .alone
        )
    }
}
