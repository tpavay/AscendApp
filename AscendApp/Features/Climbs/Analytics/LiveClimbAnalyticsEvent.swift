import Foundation

enum LiveClimbAnalyticsEvent: TelemetryEvent {
    case homeDailyTapped(climb: Climb, homeState: ClimbHomeCardState)
    case homeExploreTapped(totalClimbs: Int)
    case browseOpened(entryPoint: EntryPoint, totalClimbs: Int)
    case browsePreviewShown(climb: Climb)
    case browseClimbOpened(climb: Climb, entryPoint: EntryPoint)
    case detailViewed(climb: Climb, entryPoint: EntryPoint)
    case detailBrowseTapped(climb: Climb)
    case detailStartTapped(
        climb: Climb,
        entryPoint: EntryPoint,
        actionState: StartActionState,
        canStart: Bool
    )
    case detailStartBlocked(climb: Climb, entryPoint: EntryPoint, reason: BlockedReason)
    case headphoneHelpOpened(climb: Climb?, entryPoint: EntryPoint, surface: HeadphoneHelpSurface)
    case browseHelpOpened
    case attemptStarted(
        climb: Climb,
        entryPoint: EntryPoint
    )
    case attemptCompleted(
        climb: Climb,
        entryPoint: EntryPoint,
        durationSeconds: Int,
        steps: Int,
        rank: Int?,
        rankTotal: Int?
    )
    case attemptSaved(
        climb: Climb,
        entryPoint: EntryPoint,
        outcome: AttemptOutcome,
        durationSeconds: Int,
        steps: Int,
        progressFraction: Double
    )
    case attemptDiscarded(
        climb: Climb,
        entryPoint: EntryPoint,
        progressFraction: Double
    )
    case summaryViewed(climb: Climb, rank: Int?, rankTotal: Int?)
    case summaryShareTapped(climb: Climb, rank: Int?, rankTotal: Int?)
    case summaryDoneTapped(climb: Climb, surface: SummaryDismissSurface)
    case shareActionTapped(climb: Climb, surface: ShareSurface, cardType: ShareCardAnalyticsType)
    case shareActivityCompleted(
        climb: Climb,
        surface: ShareSurface,
        cardType: ShareCardAnalyticsType,
        completed: Bool
    )

    var record: TelemetryRecord {
        switch self {
        case .homeDailyTapped(let climb, let homeState):
            return record(
                name: "live_climb_home_daily_tap",
                climb: climb,
                parameters: [
                    "home_state": .string(Self.homeStateValue(homeState))
                ]
            )

        case .homeExploreTapped(let totalClimbs):
            return record(
                name: "live_climb_home_explore_tap",
                parameters: [
                    "total_climbs_bucket": .string(CountBucket(totalClimbs).rawValue)
                ]
            )

        case .browseOpened(let entryPoint, let totalClimbs):
            return record(
                name: "live_climb_browse_open",
                parameters: [
                    "entry_point": .string(entryPoint.rawValue),
                    "total_climbs_bucket": .string(CountBucket(totalClimbs).rawValue)
                ]
            )

        case .browsePreviewShown(let climb):
            return record(name: "live_climb_browse_preview_show", climb: climb)

        case .browseClimbOpened(let climb, let entryPoint):
            return record(
                name: "live_climb_browse_climb_open",
                climb: climb,
                parameters: [
                    "entry_point": .string(entryPoint.rawValue)
                ]
            )

        case .detailViewed(let climb, let entryPoint):
            return record(
                name: "live_climb_detail_view",
                climb: climb,
                parameters: [
                    "entry_point": .string(entryPoint.rawValue)
                ]
            )

        case .detailBrowseTapped(let climb):
            return record(name: "live_climb_detail_browse_tap", climb: climb)

        case .detailStartTapped(let climb, let entryPoint, let actionState, let canStart):
            return record(
                name: "live_climb_detail_start_tap",
                climb: climb,
                parameters: [
                    "entry_point": .string(entryPoint.rawValue),
                    "action_state": .string(actionState.rawValue),
                    "can_start": .bool(canStart)
                ]
            )

        case .detailStartBlocked(let climb, let entryPoint, let reason):
            return record(
                name: "live_climb_start_blocked",
                climb: climb,
                parameters: [
                    "entry_point": .string(entryPoint.rawValue),
                    "blocked_reason": .string(reason.rawValue)
                ]
            )

        case .headphoneHelpOpened(let climb, let entryPoint, let surface):
            let parameters: [String: TelemetryValue] = [
                "entry_point": .string(entryPoint.rawValue),
                "surface": .string(surface.rawValue)
            ]

            if let climb {
                return record(name: "live_climb_headphone_help_open", climb: climb, parameters: parameters)
            }

            return record(name: "live_climb_headphone_help_open", parameters: parameters)

        case .browseHelpOpened:
            return record(name: "live_climb_browse_help_open")

        case .attemptStarted(let climb, let entryPoint):
            return record(
                name: "live_climb_attempt_started",
                climb: climb,
                parameters: [
                    "entry_point": .string(entryPoint.rawValue)
                ]
            )

        case .attemptCompleted(let climb, let entryPoint, let durationSeconds, let steps, let rank, let rankTotal):
            return record(
                name: "live_climb_attempt_completed",
                climb: climb,
                parameters: [
                    "entry_point": .string(entryPoint.rawValue),
                    "duration_bucket": .string(DurationBucket(durationSeconds).rawValue),
                    "steps_bucket": .string(CountBucket(steps).rawValue),
                    "rank_bucket": .string(RankBucket(rank).rawValue),
                    "rank_total_bucket": .string(CountBucket(rankTotal ?? 0).rawValue)
                ]
            )

        case .attemptSaved(let climb, let entryPoint, let outcome, let durationSeconds, let steps, let progressFraction):
            return record(
                name: "live_climb_attempt_saved",
                climb: climb,
                parameters: [
                    "entry_point": .string(entryPoint.rawValue),
                    "outcome": .string(outcome.rawValue),
                    "duration_bucket": .string(DurationBucket(durationSeconds).rawValue),
                    "steps_bucket": .string(CountBucket(steps).rawValue),
                    "progress_bucket": .string(ProgressBucket(progressFraction).rawValue)
                ]
            )

        case .attemptDiscarded(let climb, let entryPoint, let progressFraction):
            return record(
                name: "live_climb_attempt_discarded",
                climb: climb,
                parameters: [
                    "entry_point": .string(entryPoint.rawValue),
                    "progress_bucket": .string(ProgressBucket(progressFraction).rawValue)
                ]
            )

        case .summaryViewed(let climb, let rank, let rankTotal):
            return record(
                name: "live_climb_summary_view",
                climb: climb,
                parameters: rankParameters(rank: rank, rankTotal: rankTotal)
            )

        case .summaryShareTapped(let climb, let rank, let rankTotal):
            return record(
                name: "live_climb_summary_share_tap",
                climb: climb,
                parameters: rankParameters(rank: rank, rankTotal: rankTotal)
            )

        case .summaryDoneTapped(let climb, let surface):
            return record(
                name: "live_climb_summary_done_tap",
                climb: climb,
                parameters: [
                    "surface": .string(surface.rawValue)
                ]
            )

        case .shareActionTapped(let climb, let surface, let cardType):
            return record(
                name: "live_climb_share_action_tap",
                climb: climb,
                parameters: [
                    "share_surface": .string(surface.rawValue),
                    "card_type": .string(cardType.rawValue)
                ]
            )

        case .shareActivityCompleted(let climb, let surface, let cardType, let completed):
            return record(
                name: "live_climb_share_activity_done",
                climb: climb,
                parameters: [
                    "share_surface": .string(surface.rawValue),
                    "card_type": .string(cardType.rawValue),
                    "completed": .bool(completed)
                ]
            )
        }
    }

    private func record(
        name: String,
        climb: Climb,
        parameters: [String: TelemetryValue] = [:]
    ) -> TelemetryRecord {
        record(
            name: name,
            parameters: Self.climbParameters(for: climb).merging(parameters) { _, newValue in newValue }
        )
    }

    private func record(
        name: String,
        parameters: [String: TelemetryValue] = [:]
    ) -> TelemetryRecord {
        TelemetryRecord(
            name: name,
            parameters: parameters,
            destinations: [.analytics]
        )
    }

    private func rankParameters(rank: Int?, rankTotal: Int?) -> [String: TelemetryValue] {
        [
            "rank_bucket": .string(RankBucket(rank).rawValue),
            "rank_total_bucket": .string(CountBucket(rankTotal ?? 0).rawValue)
        ]
    }

    private static func climbParameters(for climb: Climb) -> [String: TelemetryValue] {
        [
            "climb_id": .string(climb.id),
            "climb_tier": .string(climb.tier.rawValue),
            "climb_category": .string(climb.category),
            "climb_steps_bucket": .string(CountBucket(climb.referenceStepCount).rawValue)
        ]
    }

    private static func homeStateValue(_ state: ClimbHomeCardState) -> String {
        switch state {
        case .neverClimbed:
            return "never_climbed"
        case .inactive:
            return "inactive_completed"
        }
    }
}

extension LiveClimbAnalyticsEvent {
    enum EntryPoint: String {
        case homeDaily = "home_daily"
        case homeExplore = "home_explore"
        case workoutList = "workout_list"
        case browseSearch = "browse_search"
        case browseSection = "browse_section"
        case browseAll = "browse_all"
        case browsePin = "browse_pin"
        case browsePreview = "browse_preview"
        case detailBrowse = "detail_browse"
        case workoutDetail = "workout_detail"
        case unknown
    }

    enum StartActionState: String {
        case newAttempt = "new_attempt"
        case disabled
    }

    enum BlockedReason: String {
        case headphonesUnavailable = "headphones_unavailable"
    }

    enum HeadphoneHelpSurface: String {
        case detailHelpButton = "detail_help_button"
        case detailTrackingRow = "detail_tracking_row"
        case sessionGate = "session_gate"
    }

    enum AttemptOutcome: String {
        case active
        case completed
        case failed
        case abandoned

        init(status: ClimbAttemptStatus) {
            switch status {
            case .active:
                self = .active
            case .completed:
                self = .completed
            case .failed:
                self = .failed
            case .abandoned:
                self = .abandoned
            }
        }
    }

    enum SummaryDismissSurface: String {
        case backButton = "back_button"
        case doneButton = "done_button"
    }

    enum ShareSurface: String {
        case instagramStories = "instagram_stories"
        case systemSheet = "system_sheet"
        case copyText = "copy_text"
        case x
    }

    enum ShareCardAnalyticsType: String {
        case liveClimb = "live_climb"
        case poster
    }

    enum CountBucket: String {
        case zero
        case one
        case twoToFive = "2_5"
        case sixToTen = "6_10"
        case elevenToTwentyFive = "11_25"
        case twentySixToFifty = "26_50"
        case fiftyOneToOneHundred = "51_100"
        case oneHundredPlus = "100_plus"

        init(_ count: Int) {
            switch count {
            case ..<1:
                self = .zero
            case 1:
                self = .one
            case 2...5:
                self = .twoToFive
            case 6...10:
                self = .sixToTen
            case 11...25:
                self = .elevenToTwentyFive
            case 26...50:
                self = .twentySixToFifty
            case 51...100:
                self = .fiftyOneToOneHundred
            default:
                self = .oneHundredPlus
            }
        }
    }

    enum DurationBucket: String {
        case underFiveMinutes = "under_5_min"
        case fiveToTenMinutes = "5_10_min"
        case tenToTwentyMinutes = "10_20_min"
        case twentyToFortyFiveMinutes = "20_45_min"
        case fortyFivePlusMinutes = "45_plus_min"

        init(_ durationSeconds: Int) {
            switch max(durationSeconds, 0) {
            case ..<300:
                self = .underFiveMinutes
            case 300..<600:
                self = .fiveToTenMinutes
            case 600..<1_200:
                self = .tenToTwentyMinutes
            case 1_200..<2_700:
                self = .twentyToFortyFiveMinutes
            default:
                self = .fortyFivePlusMinutes
            }
        }
    }

    enum ProgressBucket: String {
        case zero
        case underTwentyFive = "under_25"
        case twentyFiveToFifty = "25_50"
        case fiftyToSeventyFive = "50_75"
        case seventyFiveToNinetyNine = "75_99"
        case complete

        init(_ fraction: Double) {
            switch max(0, fraction) {
            case 0:
                self = .zero
            case ..<0.25:
                self = .underTwentyFive
            case ..<0.5:
                self = .twentyFiveToFifty
            case ..<0.75:
                self = .fiftyToSeventyFive
            case ..<1:
                self = .seventyFiveToNinetyNine
            default:
                self = .complete
            }
        }
    }

    enum RankBucket: String {
        case first
        case topThree = "top_3"
        case topTen = "top_10"
        case topTwentyFive = "top_25"
        case topFifty = "top_50"
        case lower
        case unknown

        init(_ rank: Int?) {
            guard let rank, rank > 0 else {
                self = .unknown
                return
            }

            switch rank {
            case 1:
                self = .first
            case 2...3:
                self = .topThree
            case 4...10:
                self = .topTen
            case 11...25:
                self = .topTwentyFive
            case 26...50:
                self = .topFifty
            default:
                self = .lower
            }
        }
    }
}
