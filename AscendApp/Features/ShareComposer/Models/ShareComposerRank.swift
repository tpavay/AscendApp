import Foundation

/// The standing a share entry point currently knows.
///
/// A saved climb's frozen standing is read when the composer opens, so the pair can change after
/// the first frame. The two halves travel as one value so they are applied together: a rank drawn
/// over a denominator from a different read is a number that was never true.
///
/// This is not `ResolvedShareStanding`, which requires both halves. The live-completion path can
/// legitimately know a rank with no field size, and that path's rank sticker still has to resolve.
struct ShareComposerRank: Equatable {
    let rank: Int?
    let total: Int?
}
