import Foundation

/// Which stickers a climb or a period has the data to draw. A sticker with nothing to say is
/// hidden, never drawn empty.
enum StickerCatalog {
    static func climbStickers(for subject: ShareSheetSubject) -> [StickerKind] {
        StickerKind.allCases.filter { !$0.isTotals && isAvailable($0, for: subject) }
    }

    static func totalsStickers(for snapshot: ShareTotalsSnapshot) -> [StickerKind] {
        StickerKind.allCases.filter { $0.isTotals && isAvailable($0, for: snapshot) }
    }

    private static func isAvailable(_ kind: StickerKind, for subject: ShareSheetSubject) -> Bool {
        switch kind {
        case .personalRecord:
            return !subject.bestEfforts.isEmpty
        case .heartRate:
            return subject.hasHeartRate && subject.heartRateTrace.count >= 2
        case .splitsChart, .fastestSplit:
            return subject.hasSplits
        case .climbBellCurve, .climbRank:
            return subject.hasRank
        default:
            return true
        }
    }

    private static func isAvailable(_ kind: StickerKind, for snapshot: ShareTotalsSnapshot) -> Bool {
        // An empty month is still a calendar worth sharing; every other Totals sticker would
        // read as zeros.
        guard snapshot.hasClimbs else { return kind == .calendar }
        switch kind {
        case .averagePace:
            return snapshot.averagePace30Days != nil
        case .weeklyRank, .weeklyBellCurve:
            return snapshot.weekStanding != nil
        case .monthlyRank, .monthlyBellCurve:
            return snapshot.monthStanding != nil
        case .yearlyRank, .yearlyBellCurve:
            return snapshot.yearStanding != nil
        case .rankTrio:
            return snapshot.weekStanding != nil
                && snapshot.monthStanding != nil
                && snapshot.yearStanding != nil
        default:
            return true
        }
    }
}
