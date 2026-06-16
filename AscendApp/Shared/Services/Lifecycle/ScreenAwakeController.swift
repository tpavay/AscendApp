import SwiftUI
import UIKit

@MainActor
final class ScreenAwakeController {
    static let shared = ScreenAwakeController()

    private var activeRequests: [UUID: String] = [:]

    private init() {}

    func acquire(_ token: UUID, reason: String) {
        activeRequests[token] = reason
        updateIdleTimer()
    }

    func release(_ token: UUID) {
        activeRequests.removeValue(forKey: token)
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = !activeRequests.isEmpty
    }
}

private struct KeepScreenAwakeModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let isEnabled: Bool
    let reason: String

    @State private var token = UUID()
    @State private var isAcquired = false

    func body(content: Content) -> some View {
        content
            .onAppear(perform: updateRequest)
            .onDisappear(perform: releaseRequest)
            .onChange(of: isEnabled) { _, _ in
                updateRequest()
            }
            .onChange(of: scenePhase) { _, _ in
                updateRequest()
            }
    }

    private var shouldAcquire: Bool {
        isEnabled && scenePhase == .active
    }

    private func updateRequest() {
        if shouldAcquire {
            ScreenAwakeController.shared.acquire(token, reason: reason)
            isAcquired = true
        } else {
            releaseRequest()
        }
    }

    private func releaseRequest() {
        guard isAcquired else { return }
        ScreenAwakeController.shared.release(token)
        isAcquired = false
    }
}

extension View {
    func keepsScreenAwake(_ isEnabled: Bool = true, reason: String) -> some View {
        modifier(KeepScreenAwakeModifier(isEnabled: isEnabled, reason: reason))
    }
}
