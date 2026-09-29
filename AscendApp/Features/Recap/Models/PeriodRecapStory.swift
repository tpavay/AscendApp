import Foundation

/// The recap a climber sees on the first open after a week or month closes: a short
/// story of pages built once from their unseen recaps and the frozen results.
///
/// The pages are decided here, never in a view: everyone's period, then yours, then the
/// crown; one catch-up page after weeks away; a month and a week closing together end on
/// one page naming both champions.
struct PeriodRecapStory: Identifiable, Equatable, Sendable {
    /// One stop in the story.
    enum Page: Equatable, Sendable {
        case everyone(PeriodRecapCommunity)
        case yours(PeriodRecapPersonal)
        case noClimbs(PeriodRecapNoClimbs)
        case crown(PeriodRecapCrown)
        case crowns([PeriodRecapCrown])
        case catchUp(PeriodRecapCatchUp)
    }

    /// A labelled stretch of pages - one per period when a month and a week share a story.
    struct Chapter: Equatable, Sendable {
        let label: String
        let pageRange: Range<Int>
    }

    let id: String
    let pages: [Page]
    /// Empty for a single-period story, which shows one progress bar per page instead.
    let chapters: [Chapter]
    /// Every recap this story covers, including older ones folded into a catch-up, so
    /// dismissing it marks all of them seen.
    let recapIDs: [String]
    /// When the oldest period the story covers ended. Anything unseen that ended earlier is
    /// backlog the story already stands for, and is marked seen with it.
    let oldestPeriodEndAt: Date?
    /// The climber has never climbed: the story ends on their first climb.
    let isFirstClimbInvitation: Bool
}

/// Where the climber goes when the recap closes.
enum PeriodRecapExit: Equatable, Sendable {
    case close
    /// To the board that awarded the crown - "Take the crown", "Defend it".
    case openBoard(LeaderboardTimeFrame)
    /// To Home, where every climb starts.
    case startClimb
}

/// The call to action on a story's last page.
struct PeriodRecapEnding: Equatable, Sendable {
    let title: String
    let exit: PeriodRecapExit
    let showsPastChampions: Bool
}

extension PeriodRecapStory {
    /// How the story ends when `page` is its last. A climber who has never climbed is
    /// always sent to their first climb, whichever page closes the story.
    func ending(on page: Page) -> PeriodRecapEnding {
        if isFirstClimbInvitation {
            return PeriodRecapEnding(title: "START YOUR FIRST CLIMB", exit: .startClimb, showsPastChampions: false)
        }
        switch page {
        case .crown(let crown):
            return PeriodRecapEnding(
                title: crown.viewerIsChampion ? "DEFEND IT" : "TAKE THE CROWN",
                exit: .openBoard(crown.period.timeFrame),
                showsPastChampions: true
            )
        case .crowns:
            return PeriodRecapEnding(title: "CLIMB THIS WEEK", exit: .openBoard(.weekly), showsPastChampions: true)
        case .catchUp:
            return PeriodRecapEnding(title: "CLIMB TODAY", exit: .startClimb, showsPastChampions: true)
        case .noClimbs:
            return PeriodRecapEnding(title: "START A CLIMB", exit: .startClimb, showsPastChampions: false)
        case .everyone, .yours:
            return PeriodRecapEnding(title: "CLIMB THIS WEEK", exit: .openBoard(.weekly), showsPastChampions: false)
        }
    }
}

/// Everyone's period: what the whole community climbed.
struct PeriodRecapCommunity: Equatable, Sendable {
    let period: LeaderboardPeriod
    let community: LeaderboardResult.Community
}

/// The climber's own period.
struct PeriodRecapPersonal: Equatable, Sendable {
    let period: LeaderboardPeriod
    let recap: PeriodRecap.Active
    let bestEfforts: [PeriodRecapBestEffort]
}

/// A period the climber did not climb in, on one short screen.
struct PeriodRecapNoClimbs: Equatable, Sendable {
    let period: LeaderboardPeriod
    let inactive: PeriodRecap.Inactive
    let community: LeaderboardResult.Community
    let crown: PeriodRecapCrown?
}

/// Who took one period's crown, with the podium behind them.
struct PeriodRecapCrown: Equatable, Sendable {
    let title: ChampionTitle
    let period: LeaderboardPeriod
    let climberCount: Int
    let champions: [LeaderboardPlacing]
    /// Ranks 2 and 3, board order.
    let runnersUp: [LeaderboardPlacing]
    let mostClimbs: [LeaderboardPlacing]
    let mostClimbsCount: Int?
    let viewerIsChampion: Bool

    var winningSteps: Int {
        champions.first?.totalSteps ?? 0
    }

    var isTie: Bool {
        champions.count > 1
    }

    /// When the crown comes off: the end of the period after the one that was won.
    var reignEndsAt: Date? {
        period.next?.endAt
    }
}

/// Every champion a climber missed while away, one line each.
struct PeriodRecapCatchUp: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        let period: LeaderboardPeriod
        /// Nil when the period's result could not be read or crowned nobody.
        let crown: PeriodRecapCrown?
        /// Only a title still held wears its crown here.
        let isReigning: Bool
        /// The climber's own result for a period they climbed in, so a result they earned is
        /// shown before it is marked seen.
        let yours: PeriodRecap.Active?
    }

    /// Whole weeks since the climber's last climb, as the server measured it - never the
    /// number of lines, which is capped.
    let weeksAway: Int
    let lastClimbAt: Date?
    let lines: [Line]
}

/// One badge on the climber's own page.
struct PeriodRecapEarnedRow: Identifiable, Equatable, Sendable {
    let id: String
    let asset: String
    let title: String
    let detail: String
}

/// A best effort set during the period, named the way Best Efforts names it.
struct PeriodRecapBestEffort: Equatable, Sendable {
    let title: String
    let value: String
}
