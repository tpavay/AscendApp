import Foundation

/// Whether a drag callback belongs to the session already in flight, or opens a new one.
///
/// A session is dropped the moment its gesture stops being active - ended or cancelled - so
/// by the time a new touch lands there is nothing left to reuse. This is the second guard: a
/// callback naming a different block is a different gesture whatever else is in flight, and
/// must never author the block the last one was holding.
enum RoutineTimelineGesture {
    static func startsNewSession(sessionId: UUID?, intervalId: UUID) -> Bool {
        sessionId != intervalId
    }
}
