import SwiftUI

/// The period-total stickers: average pace, steps and time, floors and time, floors, the climb
/// count with its week dots, and steps beside climbs.
struct StickerTotalsContent: View {
    private enum Variant {
        case averagePace, stepsAndTime, floorsAndTime, floors, climbsAndDots, stepsAndClimbs
    }

    private static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    private let variant: Variant
    private let totals: ShareTotalsSnapshot
    let ink: StickerInk

    init?(kind: StickerKind, totals: ShareTotalsSnapshot, ink: StickerInk) {
        switch kind {
        case .averagePace:
            guard totals.averagePace30Days != nil else { return nil }
            variant = .averagePace
        case .stepsAndTime: variant = .stepsAndTime
        case .floorsAndTime: variant = .floorsAndTime
        case .floors: variant = .floors
        case .climbsAndDots: variant = .climbsAndDots
        case .stepsAndClimbs: variant = .stepsAndClimbs
        default: return nil
        }
        self.totals = totals
        self.ink = ink
    }

    var body: some View {
        switch variant {
        case .averagePace: averagePace
        case .stepsAndTime: stepsAndTime
        case .floorsAndTime: floorsAndTime
        case .floors: floors
        case .climbsAndDots: climbsAndDots
        case .stepsAndClimbs: stepsAndClimbs
        }
    }

    private var averagePace: some View {
        VStack(spacing: 0) {
            ink.text("LAST 30 DAYS", size: 7, trackingEm: 0.2, opacity: 0.85)
            ink.text(paceText, size: 38, trackingEm: -0.03, lineHeight: 0.95)
                .padding(.top, 4)
            ink.text("AVG STEPS / MIN", size: 8, trackingEm: 0.2, opacity: 0.85)
                .padding(.top, 4)
        }
    }

    private var paceText: String {
        (totals.averagePace30Days ?? 0).formatted(.number.precision(.fractionLength(1)))
    }

    private var stepsAndTime: some View {
        VStack(alignment: .leading, spacing: 8) {
            ink.text(totals.periodCaption, size: 7, trackingEm: 0.2, opacity: 0.85)
            VStack(alignment: .leading, spacing: 0) {
                ink.text(totals.stepsText, size: 26, trackingEm: -0.02, lineHeight: 1)
                ink.caption("STEPS")
            }
            VStack(alignment: .leading, spacing: 0) {
                ink.text(totals.durationText, size: 17, lineHeight: 1)
                ink.caption("TIME CLIMBING")
            }
        }
    }

    private var floorsAndTime: some View {
        VStack(alignment: .leading, spacing: 6) {
            ink.text(totals.periodCaption, size: 7, trackingEm: 0.2, opacity: 0.85)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    ink.text(totals.floorsText, size: 20, lineHeight: 1)
                    ink.caption("FLOORS")
                }
                VStack(alignment: .leading, spacing: 0) {
                    ink.text(totals.durationText, size: 20, lineHeight: 1)
                    ink.caption("TIME")
                }
            }
        }
    }

    private var floors: some View {
        VStack(spacing: 4) {
            StickerPolylineShape(points: Self.stairPoints)
                .stroke(ink.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 40, height: 28)
            ink.text(totals.floorsText, size: 36, trackingEm: -0.03, lineHeight: 0.95)
            ink.text("FLOORS \(totals.periodCaption)", size: 7, trackingEm: 0.2, opacity: 0.85)
        }
    }

    /// Three treads and three risers, in the 40 by 28 box the design draws them in.
    private static let stairPoints = [
        CGPoint(x: 2, y: 26), CGPoint(x: 11, y: 26), CGPoint(x: 11, y: 18), CGPoint(x: 20, y: 18),
        CGPoint(x: 20, y: 10), CGPoint(x: 29, y: 10), CGPoint(x: 29, y: 2), CGPoint(x: 38, y: 2)
    ]

    private var climbsAndDots: some View {
        VStack(spacing: 6) {
            ink.text(totals.climbsText, size: 44, lineHeight: 0.9)
            ink.text("CLIMBS \(totals.periodCaption)", size: 7, trackingEm: 0.2, opacity: 0.85)
            if showsWeekDots {
                HStack(spacing: 5) {
                    ForEach(Self.weekdayLetters.indices, id: \.self) { index in
                        weekDot(letter: Self.weekdayLetters[index], climbed: totals.weekDays[index])
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// The dots are Monday to Sunday of the current week, so they only belong on a week sticker.
    private var showsWeekDots: Bool {
        totals.period == .week && totals.weekDays.count == Self.weekdayLetters.count
    }

    private func weekDot(letter: String, climbed: Bool) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(climbed ? ink.color : Color.clear)
                .overlay { Circle().strokeBorder(ink.color, lineWidth: 1.5) }
                .frame(width: 10, height: 10)
            ink.numeral(letter, size: 6, opacity: 0.8)
        }
    }

    private var stepsAndClimbs: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                ink.text(totals.stepsText, size: 22, lineHeight: 1)
                ink.caption("STEPS")
            }
            Rectangle()
                .fill(ink.color)
                .frame(width: 1.5, height: 34)
                .opacity(0.6)
            VStack(alignment: .leading, spacing: 0) {
                ink.text(totals.climbsText, size: 22, lineHeight: 1)
                ink.caption("CLIMBS")
            }
        }
    }
}
