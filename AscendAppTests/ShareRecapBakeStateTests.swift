import Foundation
import Testing
@testable import AscendApp

/// A recap card is baked, so it stops tracking the standing the moment it is drawn.
///
/// The orderings that matter are the ones a climber actually produces: picking a card is the first
/// thing they do after the composer opens, which is exactly when the frozen standing is still being
/// read. Whichever way the two interleave, the card they end up exporting has to carry the rank.
struct ShareRecapBakeStateTests {
    private static let unranked = ShareComposerRank(rank: nil, total: nil)
    private static let ranked = ShareComposerRank(rank: 32, total: 85)
    private static let corrected = ShareComposerRank(rank: 31, total: 86)

    /// The window the captain's bug survived through in an earlier fix: the climber picks a card
    /// while the read is out, so the image is drawn without a rank and installed after it lands.
    @Test
    func aStandingThatLandsMidApplyRedrawsTheCardTheApplyInstalled() throws {
        var state = ShareRecapBakeState(rank: Self.unranked)
        let card = try Self.template()

        #expect(state.climberPicked(card) == .apply(card))
        #expect(state.standingChanged(to: Self.ranked) == .idle, "a second render was started mid-apply")

        let afterApply = state.applyFinished(card, renderedAgainst: Self.unranked, succeeded: true)
        #expect(afterApply == .redraw(card), "the card kept the rank-less image it was baked with")

        #expect(state.redrawFinished(renderedAgainst: Self.ranked, succeeded: true) == .idle)
        #expect(state.appliedRank == Self.ranked)
    }

    /// A standing that lands after the card is applied redraws it too, and never claims the canvas
    /// while doing so: a climber editing their card is not shown a scrim because a read landed.
    @Test
    func anAutomaticRedrawRunsWithoutClaimingTheCanvas() throws {
        var state = ShareRecapBakeState(rank: Self.unranked)
        let card = try Self.template()

        _ = state.climberPicked(card)
        #expect(state.isBakingForClimber)
        _ = state.applyFinished(card, renderedAgainst: Self.unranked, succeeded: true)
        #expect(!state.isBakingForClimber)

        #expect(state.standingChanged(to: Self.ranked) == .redraw(card))
        #expect(!state.isBakingForClimber, "an automatic redraw put a scrim over the canvas")
    }

    /// The climber's tap outranks a redraw nobody asked for: it waits for the render in flight
    /// rather than being dropped, and the composer shows straight away that it was heard.
    @Test
    func aTapDuringAnAutomaticRedrawIsRunRatherThanDropped() throws {
        var state = ShareRecapBakeState(rank: Self.unranked)
        let card = try Self.template()
        let other = try Self.template(offset: 1)

        _ = state.climberPicked(card)
        _ = state.applyFinished(card, renderedAgainst: Self.unranked, succeeded: true)
        #expect(state.standingChanged(to: Self.ranked) == .redraw(card))

        #expect(state.climberPicked(other) == .idle, "two renders were started at once")
        #expect(state.isBakingForClimber, "the climber's tap went unacknowledged")
        #expect(state.redrawFinished(renderedAgainst: Self.ranked, succeeded: true) == .apply(other))
    }

    /// A second tap while the climber's own render runs is still ignored, as it was before.
    @Test
    func aSecondTapDuringTheClimbersOwnRenderIsIgnored() throws {
        var state = ShareRecapBakeState(rank: Self.ranked)
        let card = try Self.template()
        let other = try Self.template(offset: 1)

        #expect(state.climberPicked(card) == .apply(card))
        #expect(state.climberPicked(other) == .idle)
        #expect(state.applyFinished(card, renderedAgainst: Self.ranked, succeeded: true) == .idle)
    }

    /// A render that failed leaves the card the climber has and stops. Retrying it on the spot
    /// would be a render loop, so the next standing to land is what tries again.
    @Test
    func aFailedRedrawStopsButTheNextStandingTriesAgain() throws {
        var state = ShareRecapBakeState(rank: Self.unranked)
        let card = try Self.template()

        _ = state.climberPicked(card)
        _ = state.applyFinished(card, renderedAgainst: Self.unranked, succeeded: true)
        _ = state.standingChanged(to: Self.ranked)

        #expect(state.redrawFinished(renderedAgainst: Self.ranked, succeeded: false) == .idle)
        #expect(state.appliedRank == Self.unranked, "a failed render was recorded as drawn")
        #expect(state.standingChanged(to: Self.ranked) == .redraw(card))
    }

    /// A standing can land twice, including during the redraw the first one asked for.
    @Test
    func aStandingThatMovesDuringARedrawConverges() throws {
        var state = ShareRecapBakeState(rank: Self.unranked)
        let card = try Self.template()

        _ = state.climberPicked(card)
        _ = state.applyFinished(card, renderedAgainst: Self.unranked, succeeded: true)
        #expect(state.standingChanged(to: Self.ranked) == .redraw(card))
        #expect(state.standingChanged(to: Self.corrected) == .idle)

        #expect(state.redrawFinished(renderedAgainst: Self.ranked, succeeded: true) == .redraw(card))
        #expect(state.redrawFinished(renderedAgainst: Self.corrected, succeeded: true) == .idle)
        #expect(state.appliedRank == Self.corrected)
    }

    /// An apply that failed applied nothing, so there is no card to keep current.
    @Test
    func aFailedApplyLeavesNothingApplied() throws {
        var state = ShareRecapBakeState(rank: Self.unranked)
        let card = try Self.template()

        _ = state.climberPicked(card)
        #expect(state.applyFinished(card, renderedAgainst: Self.unranked, succeeded: false) == .idle)
        #expect(state.appliedTemplate == nil)
        #expect(state.standingChanged(to: Self.ranked) == .idle)
    }

    /// A climber who picks a photograph instead is not repainted over when the standing lands.
    @Test
    func aBackgroundThatIsNotARecapEndsTheRedraws() throws {
        var state = ShareRecapBakeState(rank: Self.unranked)
        let card = try Self.template()

        _ = state.climberPicked(card)
        _ = state.applyFinished(card, renderedAgainst: Self.unranked, succeeded: true)
        state.backgroundReplaced()

        #expect(state.standingChanged(to: Self.ranked) == .idle)
    }

    private static func template(offset: Int = 0) throws -> ShareCardTemplate {
        let templates = ShareCardTemplateStore().templates(for: [.climb])
        return try #require(templates.dropFirst(offset).first, "the bundle offers no recap template")
    }
}
