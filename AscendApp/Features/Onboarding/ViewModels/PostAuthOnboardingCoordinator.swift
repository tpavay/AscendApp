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
            snapshot.isReopenedByClimber = false
            store.save(snapshot, for: userId)
            #if DEBUG
            store.endDebugReplay(for: userId)
            #endif
            SettingsManager.shared.hasCompletedBaseLevelOnboarding = true
            OnboardingAnalyticsUserProperties.setOnboardingCompleted()
            phase = .complete
            recordLifecycleSnapshot(snapshot)
        }
    }

    func moveBack() {
        guard let userId = currentUserId,
              case .onboarding(let stage) = phase,
              let currentIndex = PostAuthOnboardingStage.allCases.firstIndex(of: stage),
              currentIndex > PostAuthOnboardingStage.allCases.startIndex else { return }

        // A container stage owns no screen, so it owns no back event either: the guide sub-screen
        // the user actually tapped back on already reported the one event for that tap.
        if let context = stage.visibleScreenAnalyticsContext {
            telemetry.track(
                OnboardingAnalyticsEvent.backTapped(context: context, inputType: "button")
            )
        }

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

    /// Walks a finished climber back to the last onboarding screen, for the paywall's back control.
    ///
    /// The persisted snapshot is what routing reads, so this has to write through it rather than
    /// only moving `phase` - a forced `resolve` would otherwise snap straight back to `.complete`.
    func reopenLastStage() {
        guard let userId = currentUserId else { return }

        var snapshot = store.snapshot(for: userId)
        guard snapshot.isComplete else { return }

        snapshot.isComplete = false
        snapshot.completedAt = nil
        snapshot.isReopenedByClimber = true
        snapshot.currentStage = .firstClimb
        snapshot.completedStages.remove(.firstClimb)
        store.save(snapshot, for: userId)
        phase = .onboarding(.firstClimb)
        recordLifecycleSnapshot(snapshot)
    }

    /// Whether the climber walked back out of a finished flow themselves.
    ///
    /// `RootView` consults this before letting a loaded remote profile mark onboarding complete.
    var isReopenedByClimber: Bool {
        guard let userId = currentUserId else { return false }
        return store.snapshot(for: userId).isReopenedByClimber
    }

    func markCurrentUserComplete() {
        guard let userId = currentUserId else { return }

        store.markComplete(for: userId)
        let snapshot = store.snapshot(for: userId)
        SettingsManager.shared.hasCompletedBaseLevelOnboarding = true
        OnboardingAnalyticsUserProperties.setOnboardingCompleted()
        phase = .complete
        recordLifecycleSnapshot(snapshot)

        NotificationCenter.default.post(name: .postAuthOnboardingStateDidChange, object: nil)
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
    var lifecycleKey: String { rawValue }
}
