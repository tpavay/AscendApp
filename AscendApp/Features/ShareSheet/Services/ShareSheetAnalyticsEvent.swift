import Foundation

/// What a climber did with the share sheet: sent a card or a sticker somewhere.
enum ShareSheetAnalyticsEvent: TelemetryEvent {
    enum Action: String, Sendable {
        case story
        case copy
        case save
        case more
        case stickerCopy = "sticker_copy"
        case stickerSave = "sticker_save"
    }

    case action(Action, climbKind: String)

    var record: TelemetryRecord {
        switch self {
        case .action(let action, let climbKind):
            return TelemetryRecord(
                name: "share_sheet_action",
                parameters: [
                    "action": .string(action.rawValue),
                    "climb_kind": .string(climbKind)
                ]
            )
        }
    }
}

extension ShareSheetSubject.Kind {
    /// The kind as an analytics value.
    var analyticsValue: String {
        switch self {
        case .justClimb: return "just_climb"
        case .routine: return "routine"
        case .landmark: return "landmark"
        }
    }
}
