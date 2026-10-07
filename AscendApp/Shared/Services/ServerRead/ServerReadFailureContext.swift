import Foundation

/// What the device knew at the moment a server read failed.
///
/// The 2026-10-03 investigation could establish that the phone's Firestore stream was down and
/// could not establish why, because nothing on the phone recorded it. These three facts are what
/// separate a network handoff from a cold-launch race from a genuine fault.
struct ServerReadFailureContext: Sendable, Equatable {
    let secondsSinceLaunch: Int
    let secondsSinceForeground: Int
    let networkInterface: NetworkInterfaceKind

    @MainActor
    static func current() -> ServerReadFailureContext {
        ServerReadFailureContext(
            secondsSinceLaunch: AppActivityClock.shared.secondsSinceLaunch(),
            secondsSinceForeground: AppActivityClock.shared.secondsSinceForeground(),
            networkInterface: NetworkConnectivityService.shared.interfaceKind
        )
    }
}
