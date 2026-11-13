import Foundation

/// How long the app-access gate waits before asking again for something that did not answer.
///
/// The gate has no button to retry with, so every wait behind its spinner is on a clock. The waits
/// grow, because whatever failed a moment ago is most likely still failing, and each schedule says
/// what happens when it runs out.
struct AppAccessGateRetryPolicy: Equatable, Sendable {
    /// Waits before asking Superwall for the access paywall again, by how many attempts have failed
    /// in a row. The last wait repeats for as long as the gate is on screen: that paywall is the
    /// only way through or out of the gate, so there is nothing to fall back to and nowhere better
    /// to leave the climber than a spinner that is still trying.
    var hostedPresentationDelays: [Duration] = [
        .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32), .seconds(60)
    ]

    /// Waits before asking the server about the free week again - reading the account's record, or
    /// starting the week. When they run out the access paywall reopens.
    var freeWeekDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8)]

    /// Waits before re-reading access for a purchase Apple may already have charged for. When they
    /// run out the access paywall reopens.
    var accessCheckDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16)]

    /// How long the gate waits, once access is confirmed, for routing to take the climber into the
    /// app. Routing normally leaves the gate in the same turn, so a gate still on screen after this
    /// holds a confirmation routing does not agree with, and the access paywall reopens rather
    /// than leaving the spinner with nothing behind it.
    var routeResolutionDeadline: Duration = .seconds(10)

    func hostedPresentationDelay(afterFailures failures: Int) -> Duration {
        guard let ceiling = hostedPresentationDelays.last else { return .seconds(60) }
        return failures < hostedPresentationDelays.count
            ? hostedPresentationDelays[max(failures, 0)]
            : ceiling
    }
}
