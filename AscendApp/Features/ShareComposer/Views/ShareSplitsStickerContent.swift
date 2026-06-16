import SwiftUI

/// Structured sticker for live split data. It keeps the same text styling hooks
/// as scalar stickers, but renders rows and pace bars instead of one value.
struct ShareSplitsStickerContent: View {
    let splits: ResolvedShareSplits
    var font: ShareStickerFont = .montserrat
    var color: RGBAColor = .white
    var textBackground: ShareTextBackground = .none
    var baseValueSize: CGFloat = 26

    private var valueColor: Color { color.color }
    private var labelColor: Color {
        color.isWhite ? Color(red: 0.706, green: 0.8, blue: 0) : color.color
    }
    private var rowWidth: CGFloat { splits.hasHeartRate ? 300 : 270 }
    private var barWidth: CGFloat { splits.hasHeartRate ? 98 : 110 }

    var body: some View {
        VStack(alignment: .leading, spacing: baseValueSize * 0.38) {
            header
            divider
            columnHeader

            VStack(spacing: baseValueSize * 0.24) {
                ForEach(splits.rows) { row in
                    splitRow(row)
                }
            }
        }
        .frame(width: rowWidth, alignment: .leading)
        .shadow(color: .black.opacity(textBackground == .none ? 0.5 : 0), radius: 7, x: 0, y: 2)
        .padding(plateInsets)
        .background(plate)
        .fixedSize()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(splits.label)
                .font(font.swiftUIFont(size: baseValueSize * 0.82))
                .tracking(1.7)
                .foregroundStyle(valueColor)

            Text(splits.subtitle)
                .font(font.swiftUIFont(size: baseValueSize * 0.34))
                .tracking(1.1)
                .foregroundStyle(labelColor.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(valueColor.opacity(0.55))
            .frame(width: rowWidth, height: 1)
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            headerText("SEG", width: 42, alignment: .leading)
            headerText("SPM", width: 44, alignment: .trailing)
            Color.clear
                .frame(width: barWidth, height: 1)
            headerText("STEPS", width: 50, alignment: .trailing)
            if splits.hasHeartRate {
                headerText("HR", width: 34, alignment: .trailing)
            }
        }
        .frame(width: rowWidth)
    }

    private func splitRow(_ row: ResolvedShareSplitRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.segmentText)
                    .font(font.swiftUIFont(size: baseValueSize * 0.56))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()

                Text(row.rangeText)
                    .font(font.swiftUIFont(size: baseValueSize * 0.3))
                    .foregroundStyle(valueColor.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .monospacedDigit()
            }
            .frame(width: 42, alignment: .leading)

            Text(row.spmText)
                .font(font.swiftUIFont(size: baseValueSize * 0.62))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)

            paceBar(progress: row.progress)
                .frame(width: barWidth)

            Text(row.stepsText)
                .font(font.swiftUIFont(size: baseValueSize * 0.5))
                .foregroundStyle(valueColor.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)

            if splits.hasHeartRate {
                Text(row.heartRateText ?? "--")
                    .font(font.swiftUIFont(size: baseValueSize * 0.5))
                    .foregroundStyle(valueColor.opacity(row.heartRateText == nil ? 0.42 : 0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .frame(width: rowWidth)
    }

    private func headerText(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(font.swiftUIFont(size: baseValueSize * 0.34))
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
                        colors: [labelColor.opacity(0.55), labelColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(barWidth * min(max(progress, 0), 1), 10))
        }
        .frame(height: baseValueSize * 0.34)
    }

    private var plateInsets: EdgeInsets {
        switch textBackground {
        case .none:
            return EdgeInsets()
        default:
            return EdgeInsets(top: baseValueSize * 0.62, leading: baseValueSize * 0.68,
                              bottom: baseValueSize * 0.62, trailing: baseValueSize * 0.68)
        }
    }

    @ViewBuilder
    private var plate: some View {
        switch textBackground {
        case .none:
            EmptyView()
        case .dark:
            RoundedRectangle(cornerRadius: baseValueSize * 0.3, style: .continuous)
                .fill(.black.opacity(0.62))
        case .grey:
            RoundedRectangle(cornerRadius: baseValueSize * 0.3, style: .continuous)
                .fill(.white.opacity(0.18))
        }
    }
}

#Preview {
    ZStack {
        Image("WorkoutSharePosterBackground")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()

        ShareSplitsStickerContent(
            splits: ResolvedShareSplits(
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
            ),
            font: .spaceMono
        )
    }
}
