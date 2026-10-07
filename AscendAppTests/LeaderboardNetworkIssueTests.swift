import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// What the board tells the climber for each cause, now that there is more than one sentence.
struct LeaderboardNetworkIssueTests {
    @Test
    func aPhoneWithNoNetworkPathIsOfflineNotUnreachable() {
        #expect(LeaderboardNetworkIssue.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(LeaderboardNetworkIssue.classify(URLError(.cannotFindHost)) == .offline)
    }

    /// The timeout used to be its own `slowConnection` sentence; it is one cause with a dropped
    /// stream, so it is one sentence with it.
    @Test
    func aDroppedStreamAndATimeoutAreTheSameIssue() {
        #expect(LeaderboardNetworkIssue.classify(Firestore.error(.unavailable)) == .unreachable)
        #expect(LeaderboardNetworkIssue.classify(LeaderboardTimeoutError.operationTimedOut) == .unreachable)
        #expect(LeaderboardNetworkIssue.classify(URLError(.networkConnectionLost)) == .unreachable)
    }

    @Test
    func aRulesRefusalAndAMissingIndexAreToldApart() {
        #expect(LeaderboardNetworkIssue.classify(Firestore.error(.permissionDenied)) == .refused)
        #expect(LeaderboardNetworkIssue.classify(Firestore.error(.unauthenticated)) == .refused)
        #expect(LeaderboardNetworkIssue.classify(Firestore.error(.failedPrecondition)) == .unexpected)
    }

    @Test
    func theLineOverAStaleBoardStatesTheConditionThenTheAction() {
        #expect(LeaderboardNetworkIssue.unreachable.staleBoardMessage == "Leaderboard not updated. Pull to retry.")
        #expect(LeaderboardNetworkIssue.unexpected.staleBoardMessage == "Leaderboard not updated. Pull to retry.")
        #expect(
            LeaderboardNetworkIssue.refused.staleBoardMessage
                == "Ascend couldn't confirm your access. Pull to retry."
        )
        // Offline is the offline affordance, not a sentence.
        #expect(LeaderboardNetworkIssue.offline.staleBoardMessage == nil)
    }

    @Test
    func aRefusalNamesAccessEvenWithNoBoardToShow() {
        #expect(
            LeaderboardNetworkIssue.refused.emptyBoardMessage
                == "Ascend couldn't confirm your access. Pull to retry."
        )
    }

    /// "Cached data" is how the app stores the board, and a bare "failed" gives no next step.
    @Test(arguments: [
        LeaderboardNetworkIssue.offline,
        .unreachable,
        .refused,
        .unexpected
    ])
    func noLineSaysCachedOrLeavesTheClimberWithoutAnAction(issue: LeaderboardNetworkIssue) {
        let lines = [issue.staleBoardMessage, issue.emptyBoardMessage].compactMap { $0 }

        for line in lines {
            #expect(line.localizedCaseInsensitiveContains("cache") == false)
            #expect(line.localizedCaseInsensitiveContains("failed") == false)
            #expect(line.hasSuffix("Pull to retry."))
        }
    }
}

struct UnbrokenFinalSentenceTests {
    /// The board's lines wrap on every iPhone; the break belongs between the state and the
    /// command, not inside the command.
    @Test
    func theClosingCommandIsHeldTogetherAndTheStateStillWraps() {
        #expect(
            "Ascend couldn't confirm your access. Pull to retry.".keepingFinalSentenceUnbroken
                == "Ascend couldn't confirm your access. Pull\u{00A0}to\u{00A0}retry."
        )
    }

    @Test
    func aSingleSentenceIsLeftFreeToWrap() {
        #expect("Leaderboard stalled.".keepingFinalSentenceUnbroken == "Leaderboard stalled.")
        #expect("No climbers match".keepingFinalSentenceUnbroken == "No climbers match")
    }
}
