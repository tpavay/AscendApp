import Foundation
import Observation

@MainActor
@Observable
final class PostAuthOnboardingCoordinator {
    private let store: PostAuthOnboardingStore
    private let telemetry: TelemetryManager
    private var currentUserId: String?
    private(set) var phase: PostAuthOnboardingPhase = .signedOut

    init(
        store: PostAuthOnboardingStore = PostAuthOnboardingStore(),
        telemetry: TelemetryManager = .shared
    ) {
        self.store = store
        self.telemetry = telemetry
    }

    func resolve(userId: String?, force: Bool = false) {
        guard let userId else {
            currentUserId = nil
            phase = .signedOut
            return
        }

        guard force || currentUserId != userId || phase == .signedOut else { return }

        currentUserId = userId
        phase = .resolving

        var snapshot = store.snapshot(for: userId)
        let normalizedSnapshot = normalized(snapshot)
        if normalizedSnapshot != snapshot {
            snapshot = normalizedSnapshot
            store.save(snapshot, for: userId)
        }

        phase = snapshot.isComplete ? .complete : .onboarding(snapshot.currentStage)
        recordLifecycleSnapshot(snapshot)

        if !snapshot.isComplete {
            recordFlowStartIfNeeded(userId: userId, stage: snapshot.currentStage)
        }
    }

    func completeCurrentStage() {
        guard let userId = currentUserId,
              case .onboarding(let stage) = phase else { return }

        var snapshot = store.snapshot(for: userId)
        snapshot.completedStages.insert(stage)

        if let nextStage = stage.next {
            snapshot.currentStage = nextStage
            store.save(snapshot, for: userId)
            phase = .onboarding(nextStage)
            recordLifecycleSnapshot(snapshot)
        } else {
            snapshot.isComplete = true
            snapshot.completedAt = Date()
            store.save(snapshot, for: userId)
            #if DEBUG
            store.endDebugReplay(for: userId)
            #endif
            SettingsManager.shared.hasCompletedBaseLevelOnboarding = true
            OnboardingAnalyticsUserProperties.setOnboardingCompleted()
            phase = .complete
            recordLifecycleSnapshot(snapshot)
            recordFlowCompleted()
        }
    }

    func completeDisplayNameIfNeeded() {
        guard let userId = currentUserId,
              case .onboarding(.displayName) = phase,
              let nextStage = PostAuthOnboardingStage.displayName.next else { return }

        var snapshot = store.snapshot(for: userId)
        guard !snapshot.isComplete else { return }

        snapshot.completedStages.insert(.displayName)
        snapshot.currentStage = nextStage
        store.save(snapshot, for: userId)
        phase = .onboarding(nextStage)
        recordLifecycleSnapshot(snapshot)
    }

    func moveBack() {
        guard let userId = currentUserId,
              case .onboarding(let stage) = phase,
              let currentIndex = PostAuthOnboardingStage.allCases.firstIndex(of: stage),
              currentIndex > PostAuthOnboardingStage.allCases.startIndex else { return }

        telemetry.track(
            OnboardingAnalyticsEvent.backTapped(context: stage.analyticsContext)
        )

        let previousStage: PostAuthOnboardingStage
        if stage == .firstClimb {
            previousStage = .notifications
        } else {
            let previousIndex = PostAuthOnboardingStage.allCases.index(before: currentIndex)
            previousStage = PostAuthOnboardingStage.allCases[previousIndex]
        }

        var snapshot = store.snapshot(for: userId)
        snapshot.currentStage = previousStage
        snapshot.completedStages.remove(previousStage)
        if stage == .firstClimb {
            snapshot.completedStages.remove(.planLoading)
        }
        store.save(snapshot, for: userId)
        phase = .onboarding(previousStage)
        recordLifecycleSnapshot(snapshot)
    }

    func resetCurrentUser() {
        guard let userId = currentUserId else { return }
        store.reset(for: userId)
        let snapshot = store.snapshot(for: userId)
        phase = .onboarding(.first)
        recordLifecycleSnapshot(snapshot)
        NotificationCenter.default.post(name: .postAuthOnboardingStateDidChange, object: nil)
    }

    func markCurrentUserComplete() {
        guard let userId = currentUserId else { return }

        // Read before `markComplete` overwrites it: a user who is flipped straight to `.complete`
        // still has to close the funnel `resolve` opened, and a user who never opened one must
        // not emit a completion, or starts and completions stop being 1:1 per user.
        let wasIncompleteAfterFlowStart = store.hasRecordedFlowStart(for: userId)
            && !store.snapshot(for: userId).isComplete

        store.markComplete(for: userId)
        let snapshot = store.snapshot(for: userId)
        SettingsManager.shared.hasCompletedBaseLevelOnboarding = true
        phase = .complete
        recordLifecycleSnapshot(snapshot)

        if wasIncompleteAfterFlowStart {
            recordFlowCompleted()
        }

        NotificationCenter.default.post(name: .postAuthOnboardingStateDidChange, object: nil)
    }

    /// Both completion paths report the final stage so `onboarding_flow_completed` has one shape.
    private func recordFlowCompleted() {
        telemetry.track(
            OnboardingAnalyticsEvent.flowCompleted(context: PostAuthOnboardingStage.last.analyticsContext)
        )
    }

    private func recordFlowStartIfNeeded(userId: String, stage: PostAuthOnboardingStage) {
        guard !store.hasRecordedFlowStart(for: userId) else { return }

        store.markFlowStartRecorded(for: userId)
        telemetry.track(
            OnboardingAnalyticsEvent.flowStarted(context: stage.analyticsContext)
        )
    }

    private func recordLifecycleSnapshot(_ snapshot: PostAuthOnboardingSnapshot) {
        let completedStages = PostAuthOnboardingStage.allCases
            .filter { snapshot.completedStages.contains($0) }
            .map(\.lifecycleKey)

        if snapshot.isComplete {
            LifecycleEventRecorder.shared.recordOnboardingCompleted(
                currentStage: snapshot.currentStage.lifecycleKey,
                completedStages: completedStages
            )
        } else {
            LifecycleEventRecorder.shared.recordOnboardingStageReached(
                stage: snapshot.currentStage.lifecycleKey,
                completedStages: completedStages
            )
        }
    }

    private func normalized(_ snapshot: PostAuthOnboardingSnapshot) -> PostAuthOnboardingSnapshot {
        var normalizedSnapshot = snapshot
        normalizedSnapshot.completedStages = normalizedSnapshot.completedStages.intersection(Set(PostAuthOnboardingStage.allCases))

        if snapshot.isComplete {
            normalizedSnapshot.completedStages.formUnion(Set(PostAuthOnboardingStage.allCases))
            normalizedSnapshot.currentStage = .first
            return normalizedSnapshot
        }

        let hasIncompleteEarlierStage: Bool
        if let currentIndex = PostAuthOnboardingStage.allCases.firstIndex(of: normalizedSnapshot.currentStage) {
            let previousStages = PostAuthOnboardingStage.allCases[..<currentIndex]
            hasIncompleteEarlierStage = previousStages.contains { !normalizedSnapshot.completedStages.contains($0) }
        } else {
            hasIncompleteEarlierStage = false
        }

        if !PostAuthOnboardingStage.allCases.contains(normalizedSnapshot.currentStage) ||
            normalizedSnapshot.completedStages.contains(normalizedSnapshot.currentStage) ||
            !normalizedSnapshot.completedStages.contains(.displayName) ||
            hasIncompleteEarlierStage {
            normalizedSnapshot.currentStage = firstIncompleteStage(in: normalizedSnapshot)
        }

        return normalizedSnapshot
    }

    private func firstIncompleteStage(in snapshot: PostAuthOnboardingSnapshot) -> PostAuthOnboardingStage {
        PostAuthOnboardingStage.allCases.first { !snapshot.completedStages.contains($0) } ?? .first
    }
}

private extension PostAuthOnboardingStage {
    var lifecycleKey: String {
        switch self {
        case .displayName:
            return "display_name"
        default:
            return rawValue
        }
    }
}
