import Foundation

/// What the Apple Health card in Settings -> Integrations says and offers.
///
/// Health answers two questions here, not one: whether enrichment can read heart rate and
/// calories, and whether import can read workouts. A climber who connected before import returned
/// has the first and not the second, so the card cannot promise imports off the enrichment answer.
struct AppleHealthIntegrationStatus: Equatable {
    enum Action: Equatable {
        case none
        case connect
        case manage
    }

    enum Tone: Equatable {
        case neutral
        case connected
        case disabled
    }

    let label: String?
    let tone: Tone
    let message: String
    let action: Action

    /// `importState` is nil when import is not on offer at all: the kill switch is off.
    init(enrichment: AppleHealthConnectionState, importState: AppleHealthConnectionState?) {
        let isImportOffered = importState != nil
        let connectMessage = isImportOffered
            ? "Connect Apple Health to bring in stair stepper workouts from any device or app, and to attach heart rate and calories to the climbs you run in Ascend."
            : "Connect Apple Health to attach heart rate and calories to the climbs you run in Ascend."

        switch enrichment {
        case .unavailable:
            label = nil
            tone = .neutral
            message = "Apple Health is not available on this device."
            action = .none
        case .neverConnected:
            label = nil
            tone = .neutral
            message = connectMessage
            action = .connect
        case .revoked:
            label = "Permissions Disabled"
            tone = .disabled
            message = connectMessage
            action = .manage
        case .connected:
            switch importState {
            case nil:
                label = "Connected"
                tone = .connected
                message = "Heart rate and calories attach to the climbs you run in Ascend."
                action = .manage
            case .connected:
                label = "Connected"
                tone = .connected
                message = "Stair stepper workouts from Apple Health import as climbs, and heart rate and calories attach to the climbs you run in Ascend."
                action = .manage
            case .neverConnected, .revoked, .unavailable:
                label = nil
                tone = .neutral
                message = "Heart rate and calories attach to the climbs you run in Ascend. Connect to bring in stair stepper workouts from any device or app."
                action = .connect
            }
        }
    }
}
