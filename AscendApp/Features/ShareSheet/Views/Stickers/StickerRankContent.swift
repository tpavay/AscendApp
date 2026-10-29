import SwiftUI

/// The rank stickers: this climb's rank, the weekly, monthly and yearly ranks, and the trio.
struct StickerRankContent: View {
    /// What each sticker draws, resolved to display text so the view only lays it out.
    private enum Layout {
        /// Big centred number: the weekly rank.
        case hero(header: String, position: String, caption: String)
        /// Number with its field beside it: the monthly and per-climb ranks.
        case beside(header: String, position: String, field: String, footer: String)
        /// The ticket outline: the yearly rank.
        case ticket(header: String, position: String, caption: String)
        /// Week, month and year side by side.
        case trio(week: String, month: String, year: String)
    }

    private let layout: Layout
    let ink: StickerInk

    init?(kind: StickerKind, subject: ShareSheetSubject?, totals: ShareTotalsSnapshot?, ink: StickerInk) {
        guard let layout = Self.resolveLayout(for: kind, subject: subject, totals: totals) else { return nil }
        self.layout = layout
        self.ink = ink
    }

    var body: some View {
        switch layout {
        case let .hero(header, position, caption):
            hero(header: header, position: position, caption: caption)
        case let .beside(header, position, field, footer):
            beside(header: header, position: position, field: field, footer: footer)
        case let .ticket(header, position, caption):
            ticket(header: header, position: position, caption: caption)
        case let .trio(week, month, year):
            trio(week: week, month: month, year: year)
        }
    }

    private func hero(header: String, position: String, caption: String) -> some View {
        VStack(spacing: 0) {
            ink.text(header, size: 7, trackingEm: 0.2, opacity: 0.85)
            rankNumber(position, hashSize: 26, numberSize: 50, lineHeight: 0.9)
                .padding(.top, 4)
            ink.text(caption, size: 8, trackingEm: 0.18, opacity: 0.85)
                .padding(.top, 4)
        }
    }

    private func beside(header: String, position: String, field: String, footer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ink.text(header, size: 7, trackingEm: 0.2, opacity: 0.85)
            HStack(alignment: .bottom, spacing: 8) {
                rankNumber(position, hashSize: 22, numberSize: 46, lineHeight: 0.85)
                ink.text(field, size: 12, lineHeight: 1)
                    .padding(.bottom, 3)
            }
            ink.text(footer, size: 7, trackingEm: 0.16, opacity: 0.85)
        }
    }

    private func ticket(header: String, position: String, caption: String) -> some View {
        StickerTicketFrame(
            ink: ink,
            header: header,
            horizontalPadding: 12,
            verticalPadding: 9,
            minWidth: 120
        ) {
            VStack(alignment: .leading, spacing: 6) {
                rankNumber(position, hashSize: 16, numberSize: 32, lineHeight: 0.9, numberTrackingEm: -0.03)
                ink.text(caption, size: 8, trackingEm: 0.14)
            }
        }
    }

    private func trio(week: String, month: String, year: String) -> some View {
        VStack(spacing: 8) {
            ink.text("MY RANK \u{00B7} BY STEPS", size: 7, trackingEm: 0.2, opacity: 0.85)
            HStack(alignment: .bottom, spacing: 12) {
                trioColumn(position: week, label: "WEEK")
                trioRule
                trioColumn(position: month, label: "MONTH")
                trioRule
                trioColumn(position: year, label: "YEAR")
            }
        }
    }

    private func trioColumn(position: String, label: String) -> some View {
        VStack(spacing: 3) {
            ink.text(position, size: 24, lineHeight: 1)
            ink.caption(label)
        }
    }

    private var trioRule: some View {
        Rectangle()
            .fill(ink.color)
            .frame(width: 1.5, height: 28)
            .opacity(0.5)
    }

    /// A rank with a small `#` set on the same baseline as the number.
    private func rankNumber(
        _ position: String,
        hashSize: CGFloat,
        numberSize: CGFloat,
        lineHeight: CGFloat,
        numberTrackingEm: CGFloat = -0.04
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ink.text("#", size: hashSize)
            ink.text(position, size: numberSize, trackingEm: numberTrackingEm)
        }
        .frame(height: lineHeight * numberSize)
    }

    private static func resolveLayout(
        for kind: StickerKind,
        subject: ShareSheetSubject?,
        totals: ShareTotalsSnapshot?
    ) -> Layout? {
        switch kind {
        case .climbRank:
            guard let subject, let rank = subject.rank else { return nil }
            return .beside(
                header: "VS. \(subject.stickerFieldName)",
                position: rank.positionText,
                field: "of \(rank.fieldText)",
                footer: rank.stickerFooter
            )
        case .weeklyRank:
            guard let standing = totals?.weekStanding else { return nil }
            return .hero(
                header: "WEEKLY RANK",
                position: "\(standing.position)",
                caption: "OF \(standing.fieldText) \u{00B7} BY STEPS"
            )
        case .monthlyRank:
            guard let totals, let standing = totals.monthStanding else { return nil }
            return .beside(
                header: "\(totals.calendarMonthName.uppercased()) RANK",
                position: "\(standing.position)",
                field: "of \(standing.fieldText)",
                footer: standing.stickerFooter
            )
        case .yearlyRank:
            guard let standing = totals?.yearStanding else { return nil }
            return .ticket(
                header: "\(StickerCalendarYear.current()) RANK",
                position: "\(standing.position)",
                caption: "OF \(standing.fieldText) CLIMBERS"
            )
        case .rankTrio:
            guard let week = totals?.weekStanding,
                  let month = totals?.monthStanding,
                  let year = totals?.yearStanding else { return nil }
            return .trio(week: week.positionText, month: month.positionText, year: year.positionText)
        default:
            return nil
        }
    }
}
