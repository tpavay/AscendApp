import Foundation

/// A finish or a period total ranked against a field. The one place that decides how a standing is
/// worded, so a card and a sticker never say two different things about the same finish.
protocol ShareStanding {
    var position: Int { get }
    var field: Int { get }
    var topPercent: Int { get }
    var fieldText: String { get }
}

enum ShareStandingWording {
    /// A finish in this share of the field or better, one in two by default, is worded as `TOP 12%`.
    /// Anything lower leads with its rank (`#806`) instead, because `TOP 88%` reads as a boast the
    /// finish did not earn. A finish exactly on the line, 32nd of 64, is `TOP 50%`: it beat half.
    static let topShareLimit = 0.5

    /// A percentage of a handful is not a statement: `TOP 33% OF 3 CLIMBERS`. A field smaller than
    /// this always leads with the rank.
    static let minimumFieldForPercent = 10
}

extension ShareStanding {
    /// Whether this standing is worded as a percentage rather than a rank. Compared as exact
    /// fractions, not the rounded percent, so 458th of 914 (50.1%) never claims `TOP 50%`.
    var leadsWithPercent: Bool {
        field >= ShareStandingWording.minimumFieldForPercent
            && Double(position) / Double(field) <= ShareStandingWording.topShareLimit
    }

    /// `TOP 12%` in the top half of a real field, `#806` everywhere else.
    var headline: String {
        leadsWithPercent ? "TOP \(topPercent)%" : "#\(position)"
    }
}

extension ShareSheetSubject.Rank: ShareStanding {
    /// The caption that goes with `headline`. A field of one is the climb's first ascent, so it says
    /// that rather than `OF 1 CLIMBERS`.
    var fieldCaption: String {
        isFirstAscent ? "FIRST ASCENT" : "OF \(fieldText) CLIMBERS"
    }

    /// `BEAT 11%`, or nothing for a first ascent, which beat nobody because nobody else climbed.
    var beatCaption: String? {
        isFirstAscent ? nil : "BEAT \(beatPercent)%"
    }

    /// The rank sticker's footer: the percentile it earned, if it earned one, then what it beat.
    var stickerFooter: String {
        guard let beat = beatCaption else { return "FIRST ASCENT" }
        return leadsWithPercent ? "TOP \(topPercent)% \u{00B7} \(beat)" : beat
    }
}

extension ShareTotalsSnapshot.Standing: ShareStanding {
    /// The footer of a totals rank: `TOP 3% · BY STEPS` when it earned the percentile.
    var stickerFooter: String {
        leadsWithPercent ? "TOP \(topPercent)% \u{00B7} BY STEPS" : "BY STEPS"
    }
}
