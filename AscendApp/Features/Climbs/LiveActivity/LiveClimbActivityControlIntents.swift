import AppIntents
import Foundation

enum LiveClimbActivityCommand: String, Sendable {
    case stop
}

@MainActor
final class LiveClimbActivityCommandCenter {
    static let shared = LiveClimbActivityCommandCenter()

    private var sessionID: String?
    private var registrationID: String?
    private var handler: ((LiveClimbActivityCommand) async -> Void)?

    private init() {}

    func register(
        sessionID: String,
        registrationID: String,
        handler: @escaping (LiveClimbActivityCommand) async -> Void
    ) {
        self.sessionID = sessionID
        self.registrationID = registrationID
        self.handler = handler
    }

    func unregister(sessionID: String, registrationID: String) {
        guard self.sessionID == sessionID,
              self.registrationID == registrationID else { return }
        self.sessionID = nil
        self.registrationID = nil
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
