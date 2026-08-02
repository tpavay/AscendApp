//
//  SpyDiagnosticsRecorder.swift
//  AscendAppTests
//

import Foundation
@testable import AscendApp

/// Captures what a caller *asked* the diagnostics layer for.
final class SpyDiagnosticsRecorder: AppDiagnosticsRecording, @unchecked Sendable {
    struct Recorded {
        let name: String
        let level: AppDiagnosticEvent.Level
        let details: [String: String]
        let mirrorToCrashlytics: Bool
    }

    private let lock = NSLock()
    private var recorded: [Recorded] = []

    var events: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    @discardableResult
    func record(
        _ name: String,
        level: AppDiagnosticEvent.Level,
        details: [String: String],
        mirrorToCrashlytics: Bool
    ) -> AppDiagnosticEvent {
        lock.lock()
        recorded.append(
            Recorded(
                name: name,
                level: level,
                details: details,
                mirrorToCrashlytics: mirrorToCrashlytics
            )
        )
        lock.unlock()

        return AppDiagnosticEvent(name: name, level: level, details: details)
    }
}
