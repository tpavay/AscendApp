import Foundation

/// Decides which recap render runs next, and whether the climber asked for it.
///
/// A recap background is a snapshot: the card stops tracking the data the instant it is rendered,
/// so a standing that lands afterwards leaves an applied card asserting a rank tab it was never
/// drawn with. Ordering is the whole difficulty - an apply and a late standing interleave freely,
/// and the render that loses that race is the one a climber exports - so every render reports the
/// rank it drew against and this decides again each time one finishes. No ordering of (apply
/// starts, standing lands, apply finishes) can settle on an image baked from a stale rank.
///
/// It also keeps the two kinds of render apart. Only a render the climber asked for is allowed to
/// put a scrim over the canvas; a redraw triggered by a background read is silent, and a tap that
/// arrives during one is queued rather than dropped, because the climber's choice outranks it.
struct ShareRecapBakeState: Equatable {
    /// The render to start now.
    enum Next: Equatable {
        case idle
        /// The climber picked this card: reset the canvas onto it when it lands.
        case apply(ShareCardTemplate)
        /// The applied card is stale: redraw it and swap the image in place.
        case redraw(ShareCardTemplate)
    }

    private(set) var appliedTemplate: ShareCardTemplate?
    private(set) var appliedRank: ShareComposerRank?

    private var applying: ShareCardTemplate?
    private var redrawing: ShareCardTemplate?
    private var queuedApply: ShareCardTemplate?
    private var rank: ShareComposerRank

    init(rank: ShareComposerRank) {
        self.rank = rank
    }

    /// True while a render the climber asked for is running or waiting behind one, which is the
    /// only state the composer's dimming overlay may show.
    var isBakingForClimber: Bool {
        applying != nil || queuedApply != nil
    }

    /// The climber picked a card in the Recaps tab.
    mutating func climberPicked(_ template: ShareCardTemplate) -> Next {
        guard !isBakingForClimber else { return .idle }
        guard redrawing == nil else {
            queuedApply = template
            return .idle
        }

        applying = template
        return .apply(template)
    }

    /// A render the climber asked for finished.
    mutating func applyFinished(
        _ template: ShareCardTemplate,
        renderedAgainst rank: ShareComposerRank,
        succeeded: Bool
    ) -> Next {
        applying = nil
        if succeeded {
            appliedTemplate = template
            appliedRank = rank
        }
        return next(retryRedraw: true)
    }

    /// An automatic redraw finished.
    mutating func redrawFinished(
        renderedAgainst rank: ShareComposerRank,
        succeeded: Bool
    ) -> Next {
        redrawing = nil
        if succeeded {
            appliedRank = rank
        }
        return next(retryRedraw: succeeded)
    }

    /// A standing landed.
    mutating func standingChanged(to rank: ShareComposerRank) -> Next {
        self.rank = rank
        return next(retryRedraw: true)
    }

    /// The canvas took a background that is not this card, so there is nothing left to keep current.
    mutating func backgroundReplaced() {
        appliedTemplate = nil
        appliedRank = nil
    }

    private mutating func next(retryRedraw: Bool) -> Next {
        guard applying == nil, redrawing == nil else { return .idle }

        if let queued = queuedApply {
            queuedApply = nil
            applying = queued
            return .apply(queued)
        }

        guard retryRedraw,
              let template = appliedTemplate,
              appliedRank != rank else { return .idle }

        redrawing = template
        return .redraw(template)
    }
}
