@preconcurrency import ActivityKit
import FirebaseStorage
import Foundation

@MainActor
final class LiveClimbActivityManager {
    static let shared = LiveClimbActivityManager()

    private var activity: Activity<LiveClimbActivityAttributes>?
    private var currentAttributes: LiveClimbActivityAttributes?
    private var lastState: LiveClimbActivityAttributes.ContentState?
    private var lastUpdateAt: Date?

    private init() {}

    func start(
        climb: Climb,
        steps: Int,
        rank: Int?,
        rankTotal: Int,
        duration: TimeInterval,
        progress: Double
    ) async {
        await start(
            climb: climb,
            sessionTitle: climb.name,
            sessionSubtitle: climb.displayLocation,
            targetSteps: climb.referenceStepCount,
            steps: steps,
            rank: rank,
            rankTotal: rankTotal,
            duration: duration,
            progress: progress
        )
    }

    func start(
        climb: Climb?,
        sessionTitle: String,
        sessionSubtitle: String,
        targetSteps: Int,
        steps: Int,
        rank: Int?,
        rankTotal: Int,
        duration: TimeInterval,
        progress: Double
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        await endExistingActivities()

        let attributes = LiveClimbActivityAttributes(
            sessionID: UUID().uuidString,
            climbID: climb?.id ?? "just-climb",
            climbName: sessionTitle,
            climbLocation: sessionSubtitle,
            targetSteps: max(targetSteps, 0)
        )
        let state = makeState(
            steps: steps,
            rank: rank,
            rankTotal: rankTotal,
            duration: duration,
            progress: progress,
            status: .recording,
            photoURLString: nil
        )

        do {
            let activity = try Activity<LiveClimbActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            self.activity = activity
            currentAttributes = attributes
            lastState = state
            lastUpdateAt = Date()
        } catch {
#if DEBUG
            print("Live Climb Live Activity start failed: \(error.localizedDescription)")
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
            duration: duration,
            progress: progress,
            status: resolvedStatus,
            photoURLString: lastState?.climbPhotoURLString
        )

        guard force || shouldPublish(state) else { return }

        await activity.update(ActivityContent(state: state, staleDate: nil))
        lastState = state
        lastUpdateAt = Date()
    }

    func end(status: LiveClimbActivityStatus = .ended) async {
        let finalState = lastState.map {
            LiveClimbActivityAttributes.ContentState(
                steps: $0.steps,
                rank: $0.rank,
                rankTotal: $0.rankTotal,
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
            durationSeconds: lastState.durationSeconds,
            progress: lastState.progress,
            status: lastState.status,
            climbPhotoURLString: photoURLString,
            updatedAt: Date()
        )

        await activity.update(ActivityContent(state: state, staleDate: nil))
        self.lastState = state
        lastUpdateAt = Date()
    }

    private func shouldPublish(_ state: LiveClimbActivityAttributes.ContentState) -> Bool {
        guard let lastState else { return true }

        if state.steps != lastState.steps ||
            state.rank != lastState.rank ||
            state.rankTotal != lastState.rankTotal ||
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
        duration: TimeInterval,
        progress: Double,
        status: LiveClimbActivityStatus,
        photoURLString: String?
    ) -> LiveClimbActivityAttributes.ContentState {
        LiveClimbActivityAttributes.ContentState(
            steps: max(steps, 0),
            rank: rank,
            rankTotal: max(rankTotal, 0),
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
