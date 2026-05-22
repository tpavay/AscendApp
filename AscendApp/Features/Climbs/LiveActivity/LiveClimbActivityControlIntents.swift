import AppIntents
import Foundation

enum LiveClimbActivityCommand: String, Sendable {
    case stop
}

@MainActor
final class LiveClimbActivityCommandCenter {
    static let shared = LiveClimbActivityCommandCenter()

    private var handler: ((LiveClimbActivityCommand) async -> Void)?

    private init() {}

    func register(handler: @escaping (LiveClimbActivityCommand) async -> Void) {
        self.handler = handler
    }

    func unregister() {
        handler = nil
    }

    func perform(_ command: LiveClimbActivityCommand) async {
        await handler?(command)
    }
}

struct StopLiveClimbIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Live Climb"
    static let openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveClimbActivityCommandCenter.shared.perform(.stop)
        return .result()
    }
}
