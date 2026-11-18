import Foundation

/// The share funnel: composer opened, card chosen, share started, share finished.
///
/// The two action events keep the names `live_climb_share_action_tap` and
/// `live_climb_share_activity_done` that this file's predecessor declared and never fired, so the
/// series starts where the catalogue always said it would. They now describe any climb the
/// composer is opened on, so `climb_*` parameters are present only when the presenter has a
/// catalogue climb.
///
/// Every parameter is a member of a closed set or a bucket. Nothing a climber typed, nothing about
/// who they are, and no figure from the card ever travels.
enum ShareSheetAnalyticsEvent: TelemetryEvent {
    case composerOpened(context: ShareSheetAnalyticsContext)
    case cardSelected(context: ShareSheetAnalyticsContext, layout: PresetLayout)
    case cardEdited(context: ShareSheetAnalyticsContext, kind: ShareEditKind, value: String)
    case actionTapped(
        context: ShareSheetAnalyticsContext,
        action: ShareAction,
        content: ShareContent,
        edits: ShareEditSummary
    )
    case activityCompleted(
        context: ShareSheetAnalyticsContext,
        action: ShareAction,
        content: ShareContent,
        edits: ShareEditSummary,
        destination: ShareDestination,
        outcome: ShareOutcome
    )

    var record: TelemetryRecord {
        switch self {
        case .composerOpened(let context):
            return record(name: "share_composer_open", context: context)

        case .cardSelected(let context, let layout):
            return record(
                name: "share_card_select",
                context: context,
                parameters: ["card_layout": .string(layout.rawValue)]
            )

        case .cardEdited(let context, let kind, let value):
            return record(
                name: "share_card_edit",
                context: context,
                parameters: ["edit_type": .string(kind.rawValue), "edit_value": .string(value)]
            )

        case .actionTapped(let context, let action, let content, let edits):
            return record(
                name: "live_climb_share_action_tap",
                context: context,
                parameters: Self.actionParameters(action: action, content: content, edits: edits)
            )

        case .activityCompleted(let context, let action, let content, let edits, let destination, let outcome):
            var parameters = Self.actionParameters(action: action, content: content, edits: edits)
            parameters["destination"] = .string(destination.rawValue)
            parameters["outcome"] = .string(outcome.rawValue)
            parameters["completed"] = .bool(outcome == .completed)
            return record(name: "live_climb_share_activity_done", context: context, parameters: parameters)
        }
    }

    private func record(
        name: String,
        context: ShareSheetAnalyticsContext,
        parameters: [String: TelemetryValue] = [:]
    ) -> TelemetryRecord {
        var merged: [String: TelemetryValue] = [
            "share_source": .string(context.source.rawValue)
        ]
        if let climb = context.climb {
            merged.merge(LiveClimbAnalyticsEvent.climbParameters(for: climb)) { current, _ in current }
        }
        merged.merge(parameters) { _, new in new }
        return TelemetryRecord(name: name, parameters: merged, destinations: [.analytics])
    }

    private static func actionParameters(
        action: ShareAction,
        content: ShareContent,
        edits: ShareEditSummary
    ) -> [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "action": .string(action.rawValue)
        ]
        parameters.merge(content.parameters) { current, _ in current }
        parameters.merge(edits.parameters) { current, _ in current }
        return parameters
    }
}

/// Which surface opened the composer. Adding a presenter of `ShareSheetView` means adding a case
/// here, because the view cannot be built without one.
enum ShareSheetSource: String, Sendable, CaseIterable {
    case liveClimbSummary = "live_climb_summary"
    case workoutDetail = "workout_detail"
    case loggedClimbResult = "logged_climb_result"
}

/// What every event in one composer session shares.
struct ShareSheetAnalyticsContext: Sendable {
    let source: ShareSheetSource
    let climb: Climb?
}

/// The way out the climber chose, as a tap on the composer's own controls.
enum ShareAction: String, Sendable {
    case story
    case copy
    case save
    case more

    /// Where the action sends the content when it works, and what a failure of it is charged to.
    /// `more` has no intended destination: the climber picks one in the system sheet.
    var intendedDestination: ShareDestination {
        switch self {
        case .story: return .instagramStories
        case .copy: return .copy
        case .save: return .saveToPhotos
        case .more: return .none
        }
    }
}

/// What is being shared. A card names its layout and what is behind it, a sticker its kind and
/// whether it prints this climb or totals; none of it is the climber's own content.
enum ShareContent: Sendable, Equatable {
    case card(layout: PresetLayout, background: ShareBackgroundKind)
    case sticker(kind: String, scope: ShareStickerScope)

    var parameters: [String: TelemetryValue] {
        switch self {
        case .card(let layout, let background):
            return [
                "content_type": .string("card"),
                "card_layout": .string(layout.rawValue),
                "card_background": .string(background.rawValue)
            ]
        case .sticker(let kind, let scope):
            return [
                "content_type": .string("sticker"),
                "sticker_kind": .string(kind),
                "sticker_scope": .string(scope.rawValue)
            ]
        }
    }
}

/// What a climber can change in the sheet, as a closed set. The sheet reports that something of
/// this kind changed and, in `share_card_edit`, which member of a bounded set it changed to; it
/// never reports a figure, a name or a photograph.
enum ShareEditKind: String, Sendable, CaseIterable {
    case background
    case photo
    case font
    case accent
    case stat
    case bestEffort = "best_effort"
    case reset
    case stickerFont = "sticker_font"
    case stickerColor = "sticker_color"
    case stickerShadow = "sticker_shadow"
}

/// How much the climber changed before sharing: a bucketed count and one flag per kind, so a
/// funnel can split shares by "edited the colour" without a per-edit join.
/// It is cumulative for the sheet's lifetime, so it says what was touched, not what the shared
/// card still shows.
struct ShareEditSummary: Sendable, Equatable {
    private(set) var count = 0
    private(set) var kinds: Set<ShareEditKind> = []

    mutating func record(_ kind: ShareEditKind) {
        count += 1
        kinds.insert(kind)
    }

    var parameters: [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "edit_count_bucket": .string(LiveClimbAnalyticsEvent.CountBucket(count).rawValue)
        ]
        for kind in ShareEditKind.allCases {
            parameters["edited_\(kind.rawValue)"] = .bool(kinds.contains(kind))
        }
        return parameters
    }
}

/// The kind of background behind a card, never which tile or which photo.
enum ShareBackgroundKind: String, Sendable {
    case flat
    case seasonal
    case tower
    case photo

    init(_ background: PresetCardBackground) {
        switch background {
        case .flat: self = .flat
        case .seasonal: self = .seasonal
        case .tower: self = .tower
        case .photo: self = .photo
        }
    }
}

enum ShareStickerScope: String, Sendable {
    case climb
    case totals
}

enum ShareOutcome: String, Sendable {
    case completed
    /// The climber backed out of the system share sheet.
    case cancelled
    /// Ascend could not hand the content over: nothing rendered, Photos refused, no sheet to show.
    case failed
}

/// Where a share ended up, bucketed to a fixed set. The system sheet reports an activity type
/// string for whatever the climber picked, and that set is unbounded, so anything unrecognised is
/// `other`.
enum ShareDestination: String, Sendable {
    /// Handed to Instagram's Story composer directly. Instagram never reports whether the climber
    /// posted, so this means the hand-off happened.
    case instagramStories = "instagram_stories"
    /// Instagram's extension in the system share sheet, which offers feed, Direct and Story and
    /// does not say which one the climber used.
    case instagram
    case messages
    case whatsapp
    case airdrop
    case saveToPhotos = "save_to_photos"
    case copy
    case other
    /// No destination: the climber cancelled before picking one.
    case none

    init(activityType: String?) {
        guard let activityType = activityType?.lowercased(), !activityType.isEmpty else {
            self = .none
            return
        }
        if activityType.contains("savetocameraroll") {
            self = .saveToPhotos
        } else if activityType.contains("copytopasteboard") {
            self = .copy
        } else if activityType.contains("airdrop") {
            self = .airdrop
        } else if activityType.contains("instagram") {
            self = .instagram
        } else if activityType.contains("whatsapp") {
            self = .whatsapp
        } else if activityType.contains("message") {
            self = .messages
        } else {
            self = .other
        }
    }
}
