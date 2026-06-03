import Foundation
import Observation

@MainActor
@Observable
final class PostAuthOnboardingCoordinator {
    private let store: PostAuthOnboardingStore
    private var currentUserId: String?
    private(set) var phase: PostAuthOnboardingPhase = .signedOut

    init(store: PostAuthOnboardingStore = PostAuthOnboardingStore()) {
        self.store = store
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
            store.save(snapshot, for: userId)
            SettingsManager.shared.hasCompletedBaseLevelOnboarding = true
            phase = .complete
            recordLifecycleSnapshot(snapshot)
        }
    }

    func moveBack() {
        guard let userId = currentUserId,
              case .onboarding(let stage) = phase,
              let currentIndex = PostAuthOnboardingStage.allCases.firstIndex(of: stage),
              currentIndex > PostAuthOnboardingStage.allCases.startIndex else { return }

        let previousIndex = PostAuthOnboardingStage.allCases.index(before: currentIndex)
        let previousStage = PostAuthOnboardingStage.allCases[previousIndex]
        var snapshot = store.snapshot(for: userId)
        snapshot.currentStage = previousStage
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
        store.markComplete(for: userId)
        let snapshot = store.snapshot(for: userId)
        SettingsManager.shared.hasCompletedBaseLevelOnboarding = true
        phase = .complete
        recordLifecycleSnapshot(snapshot)
        NotificationCenter.default.post(name: .postAuthOnboardingStateDidChange, object: nil)
    }

    private func recordLifecycleSnapshot(_ snapshot: PostAuthOnboardingSnapshot) {
        let completedStages = PostAuthOnboardingStage.allCases
            .filter { snapshot.completedStages.contains($0) }
            .map(\.rawValue)

        if snapshot.isComplete {
            LifecycleEventRecorder.shared.recordOnboardingCompleted(
                currentStage: snapshot.currentStage.rawValue,
                completedStages: completedStages
            )
        } else {
            LifecycleEventRecorder.shared.recordOnboardingStageReached(
                stage: snapshot.currentStage.rawValue,
                completedStages: completedStages
            )
        }
    }

    private func normalized(_ snapshot: PostAuthOnboardingSnapshot) -> PostAuthOnboardingSnapshot {
        guard !snapshot.isComplete else { return snapshot }

        var normalizedSnapshot = snapshot
        normalizedSnapshot.completedStages = normalizedSnapshot.completedStages.intersection(Set(PostAuthOnboardingStage.allCases))

        if !PostAuthOnboardingStage.allCases.contains(normalizedSnapshot.currentStage) ||
            !normalizedSnapshot.completedStages.contains(.displayName) {
            normalizedSnapshot.currentStage = .displayName
        }

        return normalizedSnapshot
    }
}
