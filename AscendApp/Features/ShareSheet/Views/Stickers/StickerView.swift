import SwiftUI

/// One transparent sticker: its content in the climber's Font, Color and Shadow, and the Ascend
/// wordmark under it. No background, so it can be copied as a PNG with alpha.
struct StickerView: View {
    /// Room around the content so the largest shadow is not cropped when the sticker is exported.
    static let defaultBleed: CGFloat = 12

    let kind: StickerKind
    let subject: ShareSheetSubject?
    let totals: ShareTotalsSnapshot?
    let style: StickerStyle
    let bleed: CGFloat

    init(
        kind: StickerKind,
        subject: ShareSheetSubject?,
        totals: ShareTotalsSnapshot?,
        style: StickerStyle,
        bleed: CGFloat = StickerView.defaultBleed
    ) {
        self.kind = kind
        self.subject = subject
        self.totals = totals
        self.style = style
        self.bleed = bleed
    }

    var body: some View {
        let ink = StickerInk(style: style)
        VStack(spacing: 7) {
            content(ink: ink)
            AscendWordmark(size: 7, letterColor: ink.color, markColor: ink.markColor)
        }
        .stickerShadow(style)
        .padding(bleed)
        .accessibilityElement(children: .combine)
    }

    /// A kind whose data is missing draws nothing rather than a half-filled sticker; the catalog
    /// already hides such tiles, so this only guards a caller that skipped it.
    @ViewBuilder
    private func content(ink: StickerInk) -> some View {
        switch kind {
        case .stack, .strip, .list, .line, .ticket, .pace:
            if let subject, let view = StickerClimbSummaryContent(kind: kind, subject: subject, ink: ink) {
                view
            }
        case .personalRecord:
            if let subject, let view = StickerRingContent(subject: subject, ink: ink) {
                view
            }
        case .heartRate:
            if let subject, let view = StickerHeartRateContent(subject: subject, ink: ink) {
                view
            }
        case .splitsChart, .fastestSplit:
            if let subject, let view = StickerSplitsContent(kind: kind, subject: subject, ink: ink) {
                view
            }
        case .climbBellCurve, .weeklyBellCurve, .monthlyBellCurve, .yearlyBellCurve:
            if let view = StickerBellCurveContent(kind: kind, subject: subject, totals: totals, ink: ink) {
                view
            }
        case .climbRank, .weeklyRank, .monthlyRank, .yearlyRank, .rankTrio:
            if let view = StickerRankContent(kind: kind, subject: subject, totals: totals, ink: ink) {
                view
            }
        case .calendar:
            if let totals {
                StickerCalendarContent(totals: totals, ink: ink)
            }
        case .weeklySteps:
            if let totals {
                StickerBarsContent(totals: totals, ink: ink)
            }
        case .averagePace, .stepsAndTime, .floorsAndTime, .floors, .climbsAndDots, .stepsAndClimbs:
            if let totals, let view = StickerTotalsContent(kind: kind, totals: totals, ink: ink) {
                view
            }
        }
    }
}
