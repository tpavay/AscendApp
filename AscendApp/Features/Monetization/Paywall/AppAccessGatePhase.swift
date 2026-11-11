import Foundation

/// Where the app-access gate is. Every phase draws the same thing - ``AppAccessSpinnerView`` -
/// so this is what the gate is waiting on, never what it shows.
enum AppAccessGatePhase: CaseIterable, Equatable, Sendable {
    /// Superwall has been asked for the access paywall and has not put it on screen yet.
    case openingHosted
    case hostedPresented
    /// The access paywall could not open, and the gate is waiting to ask for it again.
    case awaitingHostedRetry
    /// A purchase Apple may already have charged for has not turned into access yet.
    case confirmingAccess
    case accessConfirmed
    /// Every paid offer was declined and the founder letter has been asked for.
    case openingLetter
    case letterPresented
    /// The letter is closed, or could not open, and the server is being asked about the free week.
    case startingFreeWeek
}
