import SwiftUI

/// The text-only climb stickers: Stack, Strip, List, Line, Ticket and Pace.
struct StickerClimbSummaryContent: View {
    private enum Variant {
        case stack, strip, list, line, ticket, pace
    }

    private let variant: Variant
    let subject: ShareSheetSubject
    let ink: StickerInk

    init?(kind: StickerKind, subject: ShareSheetSubject, ink: StickerInk) {
        switch kind {
        case .stack: variant = .stack
        case .strip: variant = .strip
        case .list: variant = .list
        case .line: variant = .line
        case .ticket: variant = .ticket
        case .pace: variant = .pace
        default: return nil
        }
        self.subject = subject
        self.ink = ink
    }

    var body: some View {
        switch variant {
        case .stack: stack
        case .strip: strip
        case .list: list
        case .line: line
        case .ticket: ticket
        case .pace: pace
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 0) {
            ink.text(subject.stepsText, size: 34, trackingEm: -0.03, lineHeight: 0.95)
                .padding(.top, 4)
            ink.text("STEPS", size: 8, trackingEm: 0.2, opacity: 0.85)
            HStack(spacing: 10) {
                ink.text(subject.durationText, size: 10)
                ink.text("\(subject.stepsPerMinuteText) SPM", size: 10)
            }
            .padding(.top, 6)
        }
    }

    private var strip: some View {
        HStack(alignment: .top, spacing: 12) {
            stripColumn(subject.stepsText, "STEPS")
            stripColumn(subject.durationText, "TIME")
            stripColumn(subject.stepsPerMinuteText, "SPM")
        }
    }

    private func stripColumn(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ink.text(value, size: 15)
            ink.caption(label, trackingEm: 0.14)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            listRow("STEPS", subject.stepsText)
            listRow("TIME", subject.durationText)
            listRow("STEPS / MIN", subject.stepsPerMinuteText)
        }
    }

    private func listRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ink.caption(label)
            ink.text(value, size: 17, lineHeight: 1)
        }
    }

    private var line: some View {
        ink.text("\(subject.stepsText) steps \u{00B7} \(subject.durationText)", size: 12)
    }

    private var ticket: some View {
        StickerTicketFrame(
            ink: ink,
            header: "\(subject.title.uppercased()) \u{00B7} \(subject.dateText)",
            horizontalPadding: 10,
            verticalPadding: 8,
            minWidth: nil
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    ink.text(subject.stepsText, size: 18, lineHeight: 1)
                    ink.text("STEPS", size: 8, trackingEm: 0.14)
                }
                ink.text("\(subject.durationText) \u{00B7} \(subject.stepsPerMinuteText) SPM", size: 9)
            }
        }
    }

    private var pace: some View {
        VStack(spacing: 4) {
            ink.text(subject.stepsPerMinuteText, size: 38, trackingEm: -0.03, lineHeight: 0.95)
            ink.text("STEPS / MIN", size: 8, trackingEm: 0.2, opacity: 0.85)
        }
    }
}
