import SwiftUI

/// The split-timeline table, drawn once for every card that shows splits.
///
/// A sticker and the Splits Poster used to have separate, drifting
/// implementations of this table. There is one now, parameterised by width and
/// base size, so a change to how a split reads lands everywhere at once.
struct ShareCardSplitsTable: View {
    let splits: ResolvedShareSplits
    let spec: ShareCardSplitsTableSpec
    let context: ShareCardRenderContext

    /// Column widths come from this reference layout and scale with `spec.width`.
    private enum Reference {
        static let width: Double = 270
        static let segment: Double = 42
        static let stepsPerMinute: Double = 44
        static let steps: Double = 50
        static let heartRate: Double = 34
        static let spacing: Double = 8
        /// The heart-rate column needs room, so the table widens rather than
        /// squeezing every other column.
        static let heartRateWidth: Double = 300
    }

    private var scale: Double { spec.width / Reference.width }
    private var totalWidth: Double {
        (splits.hasHeartRate ? Reference.heartRateWidth : Reference.width) * scale
    }
    private var columnSpacing: Double { Reference.spacing * scale }
    private var segmentWidth: Double { Reference.segment * scale }
    private var paceWidth: Double { Reference.stepsPerMinute * scale }
    private var stepsWidth: Double { Reference.steps * scale }
    private var heartRateWidth: Double { splits.hasHeartRate ? Reference.heartRate * scale : 0 }
    private var barWidth: Double {
        let gaps = Double(splits.hasHeartRate ? 4 : 3) * columnSpacing
        return totalWidth - segmentWidth - paceWidth - stepsWidth - heartRateWidth - gaps
    }

    private var base: Double { spec.baseSize }
    private var valueColor: Color { context.valueColor.color }
    private var accentColor: Color { context.labelColor.color }

    private var rows: [ResolvedShareSplitRow] {
        guard let maxRows = spec.maxRows else { return splits.rows }
        return Array(splits.rows.prefix(maxRows))
    }

    var body: some View {
        switch spec.layout {
        case .timeline:
            timelineTable
        case .stepQuintiles:
            stepQuintileTable
        }
    }

    private var timelineTable: some View {
        VStack(alignment: .leading, spacing: base * 0.38) {
            if spec.showsTitle {
                title
                Rectangle()
                    .fill(valueColor.opacity(0.55))
                    .frame(width: totalWidth, height: 1)
            }
            if spec.showsHeader {
                columnHeader
            }
            VStack(spacing: base * 0.24) {
                ForEach(rows) { row in
                    splitRow(row)
                }
            }
        }
        .frame(width: totalWidth, alignment: .leading)
    }

    private var stepQuintileTable: some View {
        let textColor = spec.textTint.color(in: context)

        return VStack(alignment: .leading, spacing: 7) {
            // A card wants the heading and the legend; a stat cluster writes its
            // own heading above the rows and states the average beneath them, so
            // both are the caller's call rather than the table's.
            if spec.showsTitle {
                HStack(alignment: .firstTextBaseline) {
                    Text("SPLITS BY STEP")
                        .font(context.font.swiftUIFont(size: base * 0.66, role: .heavy))
                        .tracking(1.2)
                    Spacer()
                    Text("\(splits.averageStepsPerMinuteText) AVG STEPS/MIN")
                        .font(context.font.swiftUIFont(size: base * 0.38, role: .medium))
                        .tracking(0.8)
                }
                .foregroundStyle(textColor)
            }

            ForEach(splits.stepQuintileRows.prefix(5)) { row in
                HStack(spacing: 9) {
                    // The treatment goes on each run of type, never on the row:
                    // wrapped around the bar it draws four offset copies of a
                    // solid capsule and the row grows a dark slab behind it.
                    Text(row.rangeText)
                        .frame(width: spec.width * 0.22, alignment: .leading)
                        .shareCardTextLegibility(spec.legibility)

                    GeometryReader { geometry in
                        Capsule(style: .continuous)
                            .fill(spec.trackTint.color(in: context))
                            .overlay(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(
                                        (row.isFasterThanAverage == true ? spec.fastTint : spec.slowTint)
                                            .color(in: context)
                                    )
                                    .frame(width: max(geometry.size.width * row.progress, 8))
                            }
                    }
                    .frame(height: 6)

                    Text(row.elapsedText ?? "--")
                        .frame(width: spec.width * 0.15, alignment: .trailing)
                        .shareCardTextLegibility(spec.legibility)
                }
                .font(context.font.swiftUIFont(size: base * 0.48, role: .medium))
                .foregroundStyle(textColor)
                .monospacedDigit()
            }

            if spec.showsHeader {
                Text("DARK = FASTER THAN YOUR AVERAGE")
                    .font(context.font.swiftUIFont(size: base * 0.34, role: .medium))
                    .tracking(0.9)
                    .foregroundStyle(textColor.opacity(0.56))
                    .padding(.top, 2)
            }
        }
        .frame(width: spec.width, alignment: .leading)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(splits.label)
                .font(context.font.swiftUIFont(size: base * 0.82))
                .tracking(1.7)
                .foregroundStyle(valueColor)

            Text(splits.subtitle)
                .font(context.font.swiftUIFont(size: base * 0.34))
                .tracking(1.1)
                .foregroundStyle(accentColor.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: columnSpacing) {
            headerText("SEG", width: segmentWidth, alignment: .leading)
            headerText("SPM", width: paceWidth, alignment: .trailing)
            Color.clear.frame(width: barWidth, height: 1)
            headerText("STEPS", width: stepsWidth, alignment: .trailing)
            if splits.hasHeartRate {
                headerText("HR", width: heartRateWidth, alignment: .trailing)
            }
        }
        .frame(width: totalWidth)
    }

    private func splitRow(_ row: ResolvedShareSplitRow) -> some View {
        HStack(alignment: .center, spacing: columnSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.segmentText)
                    .font(context.font.swiftUIFont(size: base * 0.56))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()

                Text(row.rangeText)
                    .font(context.font.swiftUIFont(size: base * 0.3))
                    .foregroundStyle(valueColor.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .monospacedDigit()
            }
            .frame(width: segmentWidth, alignment: .leading)

            Text(row.spmText)
                .font(context.font.swiftUIFont(size: base * 0.62))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .frame(width: paceWidth, alignment: .trailing)

            paceBar(progress: row.progress)
                .frame(width: barWidth)

            Text(row.stepsText)
                .font(context.font.swiftUIFont(size: base * 0.5))
                .foregroundStyle(valueColor.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
                .frame(width: stepsWidth, alignment: .trailing)

            if splits.hasHeartRate {
                Text(row.heartRateText ?? "--")
                    .font(context.font.swiftUIFont(size: base * 0.5))
                    .foregroundStyle(valueColor.opacity(row.heartRateText == nil ? 0.42 : 0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                    .frame(width: heartRateWidth, alignment: .trailing)
            }
        }
        .frame(width: totalWidth)
    }

    private func headerText(_ text: String, width: Double, alignment: Alignment) -> some View {
        Text(text)
            .font(context.font.swiftUIFont(size: base * 0.34))
            .tracking(1.1)
            .foregroundStyle(valueColor.opacity(0.76))
            .frame(width: width, alignment: alignment)
    }

    private func paceBar(progress: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(valueColor.opacity(0.14))

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.55), accentColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(barWidth * min(max(progress, 0), 1), 10))
        }
        .frame(height: base * 0.34)
    }
}

#Preview {
    let splits = ResolvedShareSplits(
        label: "SPLITS",
        value: "5 SEGMENTS",
        subtitle: "5 SEGMENTS · 82 SPM AVG",
        rows: [
            .init(index: 0, segmentText: "1", rangeText: "0:00-1:00", stepsText: "78", spmText: "78", heartRateText: "148", progress: 0.62),
            .init(index: 1, segmentText: "2", rangeText: "1:00-2:00", stepsText: "84", spmText: "84", heartRateText: "154", progress: 0.86),
            .init(index: 2, segmentText: "3", rangeText: "2:00-3:00", stepsText: "80", spmText: "80", heartRateText: "157", progress: 0.72),
            .init(index: 3, segmentText: "4", rangeText: "3:00-4:00", stepsText: "88", spmText: "88", heartRateText: "162", progress: 1),
            .init(index: 4, segmentText: "5", rangeText: "4:00-5:00", stepsText: "74", spmText: "74", heartRateText: nil, progress: 0.45)
        ],
        hasHeartRate: true
    )

    return ZStack {
        Color.black.ignoresSafeArea()
        ShareCardSplitsTable(
            splits: splits,
            spec: ShareCardSplitsTableSpec(),
            context: ShareCardRenderContext(splits: splits, font: .spaceMono)
        )
    }
}
