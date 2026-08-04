import CoreGraphics
import Foundation

/// Whether a drag callback belongs to the session already in flight, or opens a new one.
///
/// SwiftUI delivers no `onEnded` for a gesture the system cancels, so a session can outlive
/// the finger that opened it. A callback carrying a different block, or a touch that started
/// somewhere else, is a new gesture: it has to re-read the block it lands on, or it would
/// author from values the climber has already moved past.
enum RoutineTimelineGesture {
    static func startsNewSession(
        sessionId: UUID?,
        sessionStartLocation: CGPoint?,
        intervalId: UUID,
        startLocation: CGPoint?
    ) -> Bool {
        guard sessionId == intervalId else { return true }
        guard let startLocation, let sessionStartLocation else { return false }
        return startLocation != sessionStartLocation
    }
}
