import Foundation
import os
import os.lock

struct AppDiagnosticEvent: Codable, Identifiable, Equatable, Sendable {
    enum Level: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    let id: UUID
    let timestamp: Date
    let name: String
    let level: Level
    let details: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        name: String,
        level: Level = .info,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.level = level
        self.details = details
    }
}

final class AppDiagnosticsRecorder: @unchecked Sendable {
    static let shared = AppDiagnosticsRecorder()

    private let userDefaults: UserDefaults
    private let maxEvents: Int
    private let eventsKey = "appDiagnostics.events.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = OSAllocatedUnfairLock(initialState: ())
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ascendapp.AscendApp",
        category: "Diagnostics"
    )

    init(userDefaults: UserDefaults = .standard, maxEvents: Int = 250) {
        self.userDefaults = userDefaults
        self.maxEvents = maxEvents
    }

    @discardableResult
    func record(
        _ name: String,
        level: AppDiagnosticEvent.Level = .info,
        details: [String: String] = [:],
        mirrorToCrashlytics: Bool = true
    ) -> AppDiagnosticEvent {
        let event = AppDiagnosticEvent(
            name: name,
            level: level,
            details: sanitized(details)
        )

        lock.withLock {
            var events = loadEventsUnlocked()
            events.insert(event, at: 0)
            if events.count > maxEvents {
                events.removeLast(events.count - maxEvents)
            }
            saveEventsUnlocked(events)
        }

        writeUnifiedLog(event)

        if mirrorToCrashlytics {
            mirror(event)
        }

        return event
    }

    func recentEvents() -> [AppDiagnosticEvent] {
        lock.withLock {
            loadEventsUnlocked()
        }
    }

    func clear() {
        lock.withLock {
            userDefaults.removeObject(forKey: eventsKey)
            userDefaults.synchronize()
        }
    }

    private func loadEventsUnlocked() -> [AppDiagnosticEvent] {
        guard let data = userDefaults.data(forKey: eventsKey),
              let events = try? decoder.decode([AppDiagnosticEvent].self, from: data) else {
            return []
        }
        return events
    }

    private func saveEventsUnlocked(_ events: [AppDiagnosticEvent]) {
        guard let data = try? encoder.encode(events) else { return }
        userDefaults.set(data, forKey: eventsKey)
        userDefaults.synchronize()
    }

    private func sanitized(_ details: [String: String]) -> [String: String] {
        details.reduce(into: [:]) { result, pair in
            let key = pair.key
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "_")
                .lowercased()
            guard !key.isEmpty else { return }

            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = String(value.prefix(160))
        }
    }

    private func writeUnifiedLog(_ event: AppDiagnosticEvent) {
        let detailText = event.details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        switch event.level {
        case .info:
            logger.info("\(event.name, privacy: .public) \(detailText, privacy: .public)")
        case .warning:
            logger.warning("\(event.name, privacy: .public) \(detailText, privacy: .public)")
        case .error:
            logger.error("\(event.name, privacy: .public) \(detailText, privacy: .public)")
        }
    }

    private func mirror(_ event: AppDiagnosticEvent) {
        var parameters: [String: TelemetryValue] = [
            "diagnostic_id": .string(event.id.uuidString),
            "diagnostic_level": .string(event.level.rawValue)
        ]

        for (key, value) in event.details {
            parameters[key] = .string(crashlyticsValue(for: key, value: value))
        }

        TelemetryManager.shared.track(
            TelemetryRecord(
                name: "diagnostic:\(event.name)",
                parameters: parameters,
                destinations: [.crashlytics]
            )
        )
        TelemetryManager.shared.set(.lastDiagnosticEvent, value: event.name)
    }

    private func crashlyticsValue(for key: String, value: String) -> String {
        if key.contains("duration_seconds") ||
            key.contains("age_seconds") ||
            key.contains("unavailable_seconds") {
            return durationBucket(value)
        }

        if key == "steps" ||
            key == "target_steps" ||
            key == "sample_count" {
            return countBucket(value)
        }

        return value
    }

    private func durationBucket(_ value: String) -> String {
        guard let seconds = Int(value) else { return value }

        switch seconds {
        case ..<0:
            return "unknown"
        case 0:
            return "zero"
        case 1..<60:
            return "under_1_min"
        case 60..<300:
            return "1_5_min"
        case 300..<900:
            return "5_15_min"
        case 900..<1800:
            return "15_30_min"
        case 1800..<3600:
            return "30_60_min"
        default:
            return "60_min_plus"
        }
    }

    private func countBucket(_ value: String) -> String {
        guard let count = Int(value) else { return value }

        switch count {
        case ..<0:
            return "unknown"
        case 0:
            return "zero"
        case 1..<100:
            return "1_99"
        case 100..<500:
            return "100_499"
        case 500..<1_000:
            return "500_999"
        case 1_000..<2_500:
            return "1000_2499"
        case 2_500..<5_000:
            return "2500_4999"
        default:
            return "5000_plus"
        }
    }
}
