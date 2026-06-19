import SwiftUI
import UIKit

enum ShareRecapTemplate: String, CaseIterable, Identifiable {
    case summitPoster
    case splitsPoster
    case raceBibResult
    case glassHUD
    case officialFinish
    case bestEffortStamp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summitPoster: return "Summit Poster"
        case .splitsPoster: return "Splits Poster"
        case .raceBibResult: return "Race Bib"
        case .glassHUD: return "Glass HUD"
        case .officialFinish: return "Official Finish"
        case .bestEffortStamp: return "Best Effort"
        }
    }
}

struct ShareRecapCardData {
    let climb: Climb
    let stats: [ResolvedShareStat]
    let bestEffort: ResolvedShareStat?
    let weeklyTotals: [ResolvedShareStat]
    let splits: ResolvedShareSplits?
    let rank: Int?
    let rankTotal: Int?

    func stat(_ kind: ShareStatStickerKind) -> ResolvedShareStat? {
        stats.first { $0.kind == kind }
    }

    var climbName: String { climb.name.replacingOccurrences(of: " Climb", with: "") }
    var durationText: String { stat(.duration)?.value ?? "--" }
    var stepsText: String { stat(.steps)?.value ?? "--" }
    var caloriesText: String { stat(.calories)?.value ?? "--" }
    var paceText: String { stat(.pace)?.value ?? "--" }
    var avgHeartRateText: String { stat(.avgHeartRate)?.value ?? "--" }
    var verticalText: String { stat(.verticalClimb)?.value ?? "--" }

    var rankText: String {
        if let rank, rank > 0 { return "#\(rank)" }
        return stat(.climbRank)?.value ?? "#1"
    }

    var rankTotalText: String {
        if let rankTotal, rankTotal > 0 {
            return rankTotal.formatted(.number.grouping(.automatic))
        }
        return "the field"
    }

    var rankWithTotalText: String {
        if let value = stat(.climbRankWithTotal)?.value { return value }
        return "\(rankText) / \(rankTotalText)"
    }

    var headlineStats: [ResolvedShareStat] {
        let preferred: [ShareStatStickerKind] = [.duration, .steps, .pace, .avgHeartRate]
        let ordered = preferred.compactMap { stat($0) }
        if ordered.count >= 3 { return Array(ordered.prefix(3)) }
        return Array((ordered + stats).uniquedByLabel().prefix(3))
    }
}

struct ShareRecapCard: View {
    static let aspectRatio: CGFloat = 9.0 / 16.0
    private static let designSize = CGSize(width: 390, height: 390 / aspectRatio)

    let template: ShareRecapTemplate
    let data: ShareRecapCardData
    var climbArtworkOverride: UIImage?

    init(
        template: ShareRecapTemplate,
        data: ShareRecapCardData,
        climbArtworkOverride: UIImage? = nil
    ) {
        self.template = template
        self.data = data
        self.climbArtworkOverride = climbArtworkOverride
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width / Self.designSize.width,
                geo.size.height / Self.designSize.height
            )

            ZStack {
                templateContent(scale: 1)
                    .frame(width: Self.designSize.width, height: Self.designSize.height)
                    .scaleEffect(scale)
                    .frame(width: Self.designSize.width * scale, height: Self.designSize.height * scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .dynamicTypeSize(.large)
    }

    @ViewBuilder
    private func templateContent(scale s: CGFloat) -> some View {
        switch template {
        case .summitPoster:
            summitPoster(scale: s)
        case .splitsPoster:
            splitsPoster(scale: s)
        case .raceBibResult:
            raceBibResult(scale: s)
        case .glassHUD:
            glassHUD(scale: s)
        case .officialFinish:
            officialFinish(scale: s)
        case .bestEffortStamp:
            bestEffortStamp(scale: s)
        }
    }

    // MARK: - Templates
    //
    // Every recap is composited under the composer's always-on Ascend wordmark
    // (see ShareExportCanvas / ShareComposerView), so templates must NOT draw their
    // own wordmark at the bottom — that produced a duplicate. Race Bib keeps a
    // wordmark only because it sits in a unique spot inside the bib footer.

    private func summitPoster(scale s: CGFloat) -> some View {
        ZStack {
            artworkBackground(
                overlay: [
                    .black.opacity(0.18),
                    .black.opacity(0.34),
                    .black.opacity(0.82)
                ]
            )

            VStack(spacing: 0) {
                HStack {
                    chip("LIVE CLIMB COMPLETE", scale: s)
                    Spacer()
                    Text(data.rankText)
                        .font(.recapBold(size: 44 * s))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 30 * s)
                .padding(.top, 44 * s)

                Spacer()

                VStack(alignment: .leading, spacing: 12 * s) {
                    Text(data.climbName)
                        .font(.recapBold(size: 46 * s))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.56)

                    Text("\(data.rankWithTotalText) · \(data.stepsText) STEPS")
                        .font(.recapSemiBold(size: 12 * s))
                        .tracking(1.6 * s)
                        .foregroundStyle(Color.recapLime)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30 * s)

                metricDock(data.headlineStats, scale: s)
                    .padding(.horizontal, 24 * s)
                    .padding(.top, 28 * s)

                Spacer(minLength: 96 * s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func splitsPoster(scale s: CGFloat) -> some View {
        ZStack {
            artworkBackground(
                overlay: [
                    .black.opacity(0.42),
                    .black.opacity(0.62),
                    .black.opacity(0.9)
                ]
            )

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                Text(data.climbName)
                    .font(.recapBold(size: 42 * s))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)

                Text("SPLITS")
                    .font(.recapBold(size: 22 * s))
                    .tracking(3.5 * s)
                    .foregroundStyle(.white)
                    .padding(.top, 2 * s)

                Text(data.splits?.subtitle.uppercased() ?? "\(data.stepsText) STEPS · \(data.paceText) SPM AVG")
                    .font(.recapBold(size: 10 * s))
                    .tracking(1.5 * s)
                    .foregroundStyle(Color.recapLime)
                    .padding(.top, 8 * s)

                Divider()
                    .overlay(.white.opacity(0.65))
                    .padding(.vertical, 18 * s)

                splitRows(scale: s)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 30 * s)
            .padding(.top, 160 * s)
            .padding(.bottom, 128 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func raceBibResult(scale s: CGFloat) -> some View {
        ZStack {
            Color.hex(0xF4F1E7)

            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    artworkBackground(
                        overlay: [
                            .black.opacity(0.18),
                            .black.opacity(0.28),
                            .black.opacity(0.8)
                        ]
                    )
                    .frame(height: 310 * s)
                    .clipped()

                    VStack(alignment: .leading, spacing: 8 * s) {
                        Text("ASCEND RESULT")
                            .font(.recapBold(size: 10 * s))
                            .tracking(2 * s)
                            .foregroundStyle(Color.recapLime)

                        Text(data.climbName)
                            .font(.recapBold(size: 34 * s))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)
                    }
                    .padding(26 * s)
                }

                VStack(spacing: 18 * s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(data.rankText)
                            .font(.recapBold(size: 72 * s))
                            .foregroundStyle(.black)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 5 * s) {
                            Text("GLOBAL")
                                .font(.recapBold(size: 10 * s))
                                .tracking(2 * s)
                                .foregroundStyle(.black.opacity(0.45))
                            Text("of \(data.rankTotalText)")
                                .font(.recapBold(size: 20 * s))
                                .foregroundStyle(.black)
                        }
                    }

                    HStack(spacing: 10 * s) {
                        raceBibMetric("TIME", data.durationText, scale: s)
                        raceBibMetric("STEPS", data.stepsText, scale: s)
                        raceBibMetric("SPM", data.paceText, scale: s)
                    }

                    dashedRule(scale: s)

                    HStack {
                        AscendWordmark(size: 14 * s, letterColor: .black)
                        Spacer()
                        Text(Date.now.formatted(date: .abbreviated, time: .omitted).uppercased())
                            .font(.recapBold(size: 10 * s))
                            .tracking(1.4 * s)
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
                .padding(26 * s)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func glassHUD(scale s: CGFloat) -> some View {
        ZStack {
            artworkBackground(
                overlay: [
                    .black.opacity(0.24),
                    .black.opacity(0.48),
                    .black.opacity(0.84)
                ]
            )

            VStack(alignment: .leading, spacing: 18 * s) {
                HStack {
                    Text("ASCEND HUD")
                        .font(.recapBold(size: 11 * s))
                        .tracking(2.2 * s)
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                    Text(data.rankText)
                        .font(.recapBold(size: 22 * s))
                        .foregroundStyle(Color.recapLime)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8 * s) {
                    Text(data.climbName)
                        .font(.recapBold(size: 38 * s))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text("LIVE RESULT · \(data.stepsText) STEPS")
                        .font(.recapBold(size: 10 * s))
                        .tracking(1.8 * s)
                        .foregroundStyle(Color.recapLime)
                }

                VStack(spacing: 10 * s) {
                    ForEach(data.headlineStats, id: \.label) { stat in
                        glassMetric(stat.label, stat.value, progress: progress(for: stat), scale: s)
                    }
                }
                .padding(18 * s)
                .background(.ultraThinMaterial.opacity(0.76), in: RoundedRectangle(cornerRadius: 22 * s, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
            }
            .padding(28 * s)
            .padding(.top, 30 * s)
            .padding(.bottom, 56 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func officialFinish(scale s: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                colors: [Color.hex(0x1A1A12), .black],
                center: .top,
                startRadius: 0,
                endRadius: 660 * s
            )

            VStack(spacing: 0) {
                Text("OFFICIAL FINISH")
                    .font(.recapBold(size: 12 * s))
                    .tracking(2.7 * s)
                    .foregroundStyle(Color.recapLime)

                ZStack {
                    Circle()
                        .fill(Color.hex(0x151515))
                        .overlay(Circle().stroke(Color.hex(0xB9903E), lineWidth: 3 * s))
                        .frame(width: 190 * s, height: 190 * s)
                    Text(data.rankText)
                        .font(.recapBold(size: 70 * s))
                        .foregroundStyle(.white)
                }
                .padding(.top, 36 * s)

                Text(data.climbName)
                    .font(.recapBold(size: 38 * s))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .padding(.horizontal, 12 * s)
                    .padding(.top, 28 * s)

                Text("Finished \(data.rankWithTotalText)")
                    .font(.recapMedium(size: 15 * s))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 8 * s)

                Spacer()

                metricDock(data.headlineStats, scale: s)
            }
            .padding(28 * s)
            .padding(.top, 48 * s)
            .padding(.bottom, 56 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func bestEffortStamp(scale s: CGFloat) -> some View {
        ZStack {
            artworkBackground(
                overlay: [
                    .black.opacity(0.36),
                    .black.opacity(0.58),
                    .black.opacity(0.9)
                ]
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color.recapLime, style: StrokeStyle(lineWidth: 4 * s, dash: [8 * s, 7 * s]))
                            .frame(width: 158 * s, height: 158 * s)
                        VStack(spacing: 4 * s) {
                            Text("BEST")
                                .font(.recapBold(size: 17 * s))
                            Text("EFFORT")
                                .font(.recapBold(size: 17 * s))
                            Text(data.bestEffort?.label ?? "CLIMB")
                                .font(.recapBold(size: 8 * s))
                                .tracking(1.3 * s)
                        }
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-12))
                    }
                }

                Spacer()

                Text(data.bestEffort?.value ?? data.rankText)
                    .font(.recapBold(size: 70 * s))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(data.bestEffort?.label ?? "GLOBAL RANK")
                    .font(.recapBold(size: 12 * s))
                    .tracking(2.2 * s)
                    .foregroundStyle(Color.recapLime)

                Text(data.climbName)
                    .font(.recapBold(size: 32 * s))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .padding(.top, 22 * s)

                metricDock(data.headlineStats, scale: s)
                    .padding(.top, 24 * s)
            }
            .padding(28 * s)
            .padding(.top, 42 * s)
            .padding(.bottom, 56 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func artworkBackground(overlay colors: [Color]) -> some View {
        // Lay the artwork on a flexible Color.clear base via overlays rather than
        // as a ZStack sizing member. A landscape hero's `scaledToFill` reports an
        // overflowed width even under `.frame(maxWidth:.infinity).clipped()` — used
        // directly in a ZStack that width drove the whole template, stretching the
        // stat overlays off-card and center-cropping them. As an overlay it can
        // overflow visually (and clip) without ever growing the card's layout.
        Color.clear
            .overlay {
                if let climbArtworkOverride {
                    Image(uiImage: climbArtworkOverride)
                        .resizable()
                        .scaledToFill()
                } else {
                    ClimbArtworkView(climb: data.climb, variant: .hero)
                }
            }
            .overlay {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            }
            .clipped()
    }

    private func chip(_ text: String, scale s: CGFloat) -> some View {
        Text(text)
            .font(.recapBold(size: 9 * s))
            .tracking(1.5 * s)
            .foregroundStyle(.white)
            .padding(.horizontal, 13 * s)
            .padding(.vertical, 9 * s)
            .background(.white.opacity(0.13), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
    }

    private func metricDock(_ stats: [ResolvedShareStat], scale s: CGFloat) -> some View {
        let visibleStats = Array(stats.prefix(3))

        return HStack(spacing: 0) {
            ForEach(visibleStats, id: \.label) { stat in
                metricDockCell(stat, scale: s)
            }
        }
        .padding(.vertical, 17 * s)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22 * s, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func metricDockCell(_ stat: ResolvedShareStat, scale s: CGFloat) -> some View {
        VStack(spacing: 5 * s) {
            Text(stat.value)
                .font(.recapBold(size: 22 * s))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(shortLabel(stat.label))
                .font(.recapBold(size: 8 * s))
                .tracking(1.4 * s)
                .foregroundStyle(Color.recapLime)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func splitRows(scale s: CGFloat) -> some View {
        if let splits = data.splits, !splits.rows.isEmpty {
            splitRowsList(rows: Array(splits.rows.prefix(6)), scale: s)
        } else {
            Text("SPLITS UNAVAILABLE")
                .font(.recapBold(size: 15 * s))
                .tracking(2 * s)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func splitRowsList(rows: [ResolvedShareSplitRow], scale s: CGFloat) -> some View {
        VStack(spacing: 12 * s) {
            splitHeader(scale: s)
            ForEach(rows) { row in
                splitRow(row, scale: s)
            }
        }
    }

    private func splitHeader(scale s: CGFloat) -> some View {
        HStack {
            Text("SEG")
            Text("SPM").frame(width: 92 * s, alignment: .leading)
            Spacer()
            Text("STEPS").frame(width: 58 * s, alignment: .trailing)
            Text("HR").frame(width: 42 * s, alignment: .trailing)
        }
        .font(.recapBold(size: 9 * s))
        .tracking(1.6 * s)
        .foregroundStyle(.white.opacity(0.64))
    }

    private func splitRow(_ row: ResolvedShareSplitRow, scale s: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12 * s) {
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(row.segmentText)
                    .font(.recapBold(size: 21 * s))
                    .foregroundStyle(.white)
                Text(row.rangeText)
                    .font(.recapBold(size: 8 * s))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(width: 48 * s, alignment: .leading)

            Text(row.spmText)
                .font(.recapBold(size: 20 * s))
                .foregroundStyle(.white)
                .frame(width: 38 * s, alignment: .leading)

            splitProgressBar(progress: row.progress, scale: s)

            Text(row.stepsText)
                .font(.recapBold(size: 17 * s))
                .foregroundStyle(.white)
                .frame(width: 58 * s, alignment: .trailing)

            Text(row.heartRateText ?? "--")
                .font(.recapBold(size: 17 * s))
                .foregroundStyle(.white.opacity(row.heartRateText == nil ? 0.5 : 1))
                .frame(width: 42 * s, alignment: .trailing)
        }
    }

    private func splitProgressBar(progress: Double, scale s: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(.white.opacity(0.13))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.recapLime)
                        .frame(width: max(16 * s, geo.size.width * progress))
                }
        }
        .frame(height: 12 * s)
    }

    private func raceBibMetric(_ label: String, _ value: String, scale s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5 * s) {
            Text(label)
                .font(.recapBold(size: 8 * s))
                .tracking(1.4 * s)
                .foregroundStyle(.black.opacity(0.46))
            Text(value)
                .font(.recapBold(size: 20 * s))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12 * s)
        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
    }

    private func glassMetric(_ label: String, _ value: String, progress: Double, scale s: CGFloat) -> some View {
        HStack(spacing: 12 * s) {
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(shortLabel(label))
                    .font(.recapBold(size: 8 * s))
                    .tracking(1.5 * s)
                    .foregroundStyle(.white.opacity(0.48))
                Text(value)
                    .font(.recapBold(size: 20 * s))
                    .foregroundStyle(.white)
            }
            .frame(width: 104 * s, alignment: .leading)

            GeometryReader { geo in
                Capsule()
                    .fill(.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.recapLime)
                            .frame(width: geo.size.width * progress)
                    }
            }
            .frame(height: 10 * s)
        }
    }

    private func dashedRule(scale s: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay {
                GeometryReader { geo in
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(.black.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [7 * s, 6 * s]))
                }
            }
    }

    private func progress(for stat: ResolvedShareStat) -> Double {
        switch stat.kind {
        case .duration: return 0.72
        case .steps: return 0.84
        case .pace: return 0.66
        case .avgHeartRate, .maxHeartRate: return 0.58
        default: return 0.62
        }
    }

    private func shortLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: " THIS WEEK", with: "")
            .replacingOccurrences(of: "AVG BPM", with: "AVG HR")
            .replacingOccurrences(of: "MAX BPM", with: "MAX HR")
    }
}

private extension Array where Element == ResolvedShareStat {
    func uniquedByLabel() -> [ResolvedShareStat] {
        var seen = Set<String>()
        return filter { seen.insert($0.label).inserted }
    }
}

private extension Font {
    static func recapBold(size: CGFloat) -> Font {
        Font.custom("Montserrat-Bold", fixedSize: size)
    }

    static func recapSemiBold(size: CGFloat) -> Font {
        Font.custom("Montserrat-SemiBold", fixedSize: size)
    }

    static func recapMedium(size: CGFloat) -> Font {
        Font.custom("Montserrat-Medium", fixedSize: size)
    }
}

private extension Color {
    static let recapLime = Color(red: 0.706, green: 0.8, blue: 0)

    static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
