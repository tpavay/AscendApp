import SwiftUI
import UIKit

enum ShareRecapTemplate: String, CaseIterable, Identifiable {
    case summitPoster
    case splitsPoster
    case raceBibResult
    case crownChase
    case glassHUD
    case wrappedData
    case blueprintClimb
    case officialFinish
    case bestEffortStamp
    case weeklyRecap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summitPoster: return "Summit Poster"
        case .splitsPoster: return "Splits Poster"
        case .raceBibResult: return "Race Bib"
        case .crownChase: return "Crown Chase"
        case .glassHUD: return "Glass HUD"
        case .wrappedData: return "Wrapped Data"
        case .blueprintClimb: return "Blueprint"
        case .officialFinish: return "Official Finish"
        case .bestEffortStamp: return "Best Effort"
        case .weeklyRecap: return "Weekly Recap"
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

    var weeklyDisplayStats: [ResolvedShareStat] {
        if !weeklyTotals.isEmpty { return weeklyTotals }
        return [
            ResolvedShareStat(kind: .totals, label: "STEPS THIS WEEK", value: stepsText),
            ResolvedShareStat(kind: .totals, label: "TIME THIS WEEK", value: durationText),
            ResolvedShareStat(kind: .totals, label: "VERTICAL THIS WEEK", value: verticalText)
        ]
    }
}

struct ShareRecapCard: View {
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
            let s = geo.size.width / 390

            ZStack {
                switch template {
                case .summitPoster:
                    summitPoster(scale: s)
                case .splitsPoster:
                    splitsPoster(scale: s)
                case .raceBibResult:
                    raceBibResult(scale: s)
                case .crownChase:
                    crownChase(scale: s)
                case .glassHUD:
                    glassHUD(scale: s)
                case .wrappedData:
                    wrappedData(scale: s)
                case .blueprintClimb:
                    blueprintClimb(scale: s)
                case .officialFinish:
                    officialFinish(scale: s)
                case .bestEffortStamp:
                    bestEffortStamp(scale: s)
                case .weeklyRecap:
                    weeklyRecap(scale: s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    // MARK: - Templates

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
                        .font(.montserratBold(size: 44 * s))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 30 * s)
                .padding(.top, 44 * s)

                Spacer()

                VStack(alignment: .leading, spacing: 12 * s) {
                    Text(data.climbName)
                        .font(.montserratBold(size: 46 * s))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.56)

                    Text("\(data.rankWithTotalText) · \(data.stepsText) STEPS")
                        .font(.montserratSemiBold(size: 12 * s))
                        .tracking(1.6 * s)
                        .foregroundStyle(Color.recapLime)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30 * s)

                metricDock(data.headlineStats, scale: s)
                    .padding(.horizontal, 24 * s)
                    .padding(.top, 28 * s)

                Spacer(minLength: 72 * s)
            }

            VStack {
                Spacer()
                AscendWordmark(size: 16 * s, letterColor: .white.opacity(0.94))
                    .padding(.bottom, 34 * s)
            }
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
                    .font(.montserratBold(size: 42 * s))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)

                Text("SPLITS")
                    .font(.montserratBold(size: 22 * s))
                    .tracking(3.5 * s)
                    .foregroundStyle(.white)
                    .padding(.top, 2 * s)

                Text(data.splits?.subtitle.uppercased() ?? "\(data.stepsText) STEPS · \(data.paceText) SPM AVG")
                    .font(.montserratBold(size: 10 * s))
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
            .padding(.bottom, 116 * s)

            VStack {
                Spacer()
                AscendWordmark(size: 16 * s, letterColor: .white.opacity(0.94))
                    .padding(.bottom, 36 * s)
            }
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
                            .font(.montserratBold(size: 10 * s))
                            .tracking(2 * s)
                            .foregroundStyle(Color.recapLime)

                        Text(data.climbName)
                            .font(.montserratBold(size: 34 * s))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)
                    }
                    .padding(26 * s)
                }

                VStack(spacing: 18 * s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(data.rankText)
                            .font(.montserratBold(size: 72 * s))
                            .foregroundStyle(.black)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 5 * s) {
                            Text("GLOBAL")
                                .font(.montserratBold(size: 10 * s))
                                .tracking(2 * s)
                                .foregroundStyle(.black.opacity(0.45))
                            Text("of \(data.rankTotalText)")
                                .font(.montserratBold(size: 20 * s))
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
                            .font(.montserratBold(size: 10 * s))
                            .tracking(1.4 * s)
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
                .padding(26 * s)

                Spacer(minLength: 0)
            }
        }
    }

    private func crownChase(scale s: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color.hex(0x101712), .black],
                startPoint: .top,
                endPoint: .bottom
            )

            mountainMark(scale: s)
                .fill(.white.opacity(0.055))
                .frame(width: 470 * s, height: 260 * s)
                .offset(y: -70 * s)

            VStack(alignment: .leading, spacing: 0) {
                Text("CROWN CHASE")
                    .font(.montserratBold(size: 12 * s))
                    .tracking(2.6 * s)
                    .foregroundStyle(Color.recapLime)

                Text(data.climbName)
                    .font(.montserratBold(size: 40 * s))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .padding(.top, 12 * s)

                Text("You finished \(data.rankText) out of \(data.rankTotalText).")
                    .font(.montserratMedium(size: 15 * s))
                    .foregroundStyle(.white.opacity(0.66))
                    .padding(.top, 8 * s)

                Spacer()

                VStack(spacing: 10 * s) {
                    podiumRow(place: "1", name: "Champion", value: "CROWN", highlighted: data.rank == 1, scale: s)
                    podiumRow(place: data.rankText.replacingOccurrences(of: "#", with: ""), name: "You", value: data.stepsText, highlighted: true, scale: s)
                    podiumRow(place: "TOP", name: "Field", value: data.rankTotalText, highlighted: false, scale: s)
                }

                metricDock(data.headlineStats, scale: s)
                    .padding(.top, 22 * s)

                AscendWordmark(size: 14 * s, letterColor: .white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36 * s)
            }
            .padding(30 * s)
            .padding(.top, 24 * s)
            .padding(.bottom, 28 * s)
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
                        .font(.montserratBold(size: 11 * s))
                        .tracking(2.2 * s)
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                    Text(data.rankText)
                        .font(.montserratBold(size: 22 * s))
                        .foregroundStyle(Color.recapLime)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8 * s) {
                    Text(data.climbName)
                        .font(.montserratBold(size: 38 * s))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text("LIVE RESULT · \(data.stepsText) STEPS")
                        .font(.montserratBold(size: 10 * s))
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

                AscendWordmark(size: 14 * s, letterColor: .white.opacity(0.92))
                    .frame(maxWidth: .infinity)
            }
            .padding(28 * s)
            .padding(.top, 30 * s)
            .padding(.bottom, 34 * s)
        }
    }

    private func wrappedData(scale s: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.hex(0xB4CC00), Color.hex(0x101010), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.black.opacity(0.2))
                .frame(width: 430 * s, height: 430 * s)
                .offset(x: 120 * s, y: -170 * s)

            VStack(alignment: .leading, spacing: 18 * s) {
                Text("YOUR CLIMB WRAPPED")
                    .font(.montserratBold(size: 13 * s))
                    .tracking(2 * s)
                    .foregroundStyle(.black.opacity(0.78))

                Text(data.climbName)
                    .font(.montserratBold(size: 42 * s))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)

                Spacer()

                VStack(spacing: 12 * s) {
                    wrappedMetric(rank: "01", label: "RANK", value: data.rankText, scale: s)
                    wrappedMetric(rank: "02", label: "STEPS", value: data.stepsText, scale: s)
                    wrappedMetric(rank: "03", label: "PACE", value: "\(data.paceText) SPM", scale: s)
                    wrappedMetric(rank: "04", label: "TIME", value: data.durationText, scale: s)
                }

                Spacer()

                AscendWordmark(size: 15 * s, letterColor: .white.opacity(0.94))
                    .frame(maxWidth: .infinity)
            }
            .padding(28 * s)
            .padding(.top, 34 * s)
            .padding(.bottom, 34 * s)
        }
    }

    private func blueprintClimb(scale s: CGFloat) -> some View {
        ZStack {
            Color.hex(0x071018)
            blueprintGrid(scale: s)
                .stroke(Color.recapLime.opacity(0.13), lineWidth: 0.8 * s)

            VStack(alignment: .leading, spacing: 0) {
                Text("CLIMB BLUEPRINT")
                    .font(.montserratBold(size: 11 * s))
                    .tracking(2.2 * s)
                    .foregroundStyle(Color.recapLime)

                Text(data.climbName)
                    .font(.montserratBold(size: 38 * s))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .padding(.top, 10 * s)

                ZStack(alignment: .bottomLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 210 * s))
                        path.addLine(to: CGPoint(x: 70 * s, y: 210 * s))
                        path.addLine(to: CGPoint(x: 70 * s, y: 160 * s))
                        path.addLine(to: CGPoint(x: 142 * s, y: 160 * s))
                        path.addLine(to: CGPoint(x: 142 * s, y: 110 * s))
                        path.addLine(to: CGPoint(x: 214 * s, y: 110 * s))
                        path.addLine(to: CGPoint(x: 214 * s, y: 58 * s))
                        path.addLine(to: CGPoint(x: 292 * s, y: 58 * s))
                    }
                    .stroke(Color.recapLime, style: StrokeStyle(lineWidth: 8 * s, lineCap: .square, lineJoin: .miter))

                    Text(data.stepsText)
                        .font(.montserratBold(size: 64 * s))
                        .foregroundStyle(.white.opacity(0.96))
                        .offset(x: 10 * s, y: -16 * s)
                }
                .frame(height: 250 * s)
                .padding(.top, 30 * s)

                Spacer()

                VStack(spacing: 8 * s) {
                    blueprintMetric("DURATION", data.durationText, scale: s)
                    blueprintMetric("VERTICAL", data.verticalText, scale: s)
                    blueprintMetric("RANK", data.rankWithTotalText, scale: s)
                }

                AscendWordmark(size: 14 * s, letterColor: .white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 34 * s)
            }
            .padding(28 * s)
            .padding(.top, 34 * s)
            .padding(.bottom, 32 * s)
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
                    .font(.montserratBold(size: 12 * s))
                    .tracking(2.7 * s)
                    .foregroundStyle(Color.recapLime)

                ZStack {
                    Circle()
                        .fill(Color.hex(0x151515))
                        .overlay(Circle().stroke(Color.hex(0xB9903E), lineWidth: 3 * s))
                        .frame(width: 190 * s, height: 190 * s)
                    Text(data.rankText)
                        .font(.montserratBold(size: 70 * s))
                        .foregroundStyle(.white)
                }
                .padding(.top, 36 * s)

                Text(data.climbName)
                    .font(.montserratBold(size: 38 * s))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .padding(.horizontal, 12 * s)
                    .padding(.top, 28 * s)

                Text("Finished \(data.rankWithTotalText)")
                    .font(.montserratMedium(size: 15 * s))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 8 * s)

                Spacer()

                metricDock(data.headlineStats, scale: s)

                AscendWordmark(size: 15 * s, letterColor: .white.opacity(0.94))
                    .padding(.top, 38 * s)
            }
            .padding(28 * s)
            .padding(.top, 48 * s)
            .padding(.bottom, 34 * s)
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
                                .font(.montserratBold(size: 17 * s))
                            Text("EFFORT")
                                .font(.montserratBold(size: 17 * s))
                            Text(data.bestEffort?.label ?? "CLIMB")
                                .font(.montserratBold(size: 8 * s))
                                .tracking(1.3 * s)
                        }
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-12))
                    }
                }

                Spacer()

                Text(data.bestEffort?.value ?? data.rankText)
                    .font(.montserratBold(size: 70 * s))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(data.bestEffort?.label ?? "GLOBAL RANK")
                    .font(.montserratBold(size: 12 * s))
                    .tracking(2.2 * s)
                    .foregroundStyle(Color.recapLime)

                Text(data.climbName)
                    .font(.montserratBold(size: 32 * s))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .padding(.top, 22 * s)

                metricDock(data.headlineStats, scale: s)
                    .padding(.top, 24 * s)

                AscendWordmark(size: 14 * s, letterColor: .white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36 * s)
            }
            .padding(28 * s)
            .padding(.top, 42 * s)
            .padding(.bottom, 34 * s)
        }
    }

    private func weeklyRecap(scale s: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color.hex(0x10140D), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                Text("ASCEND WEEKLY")
                    .font(.montserratBold(size: 12 * s))
                    .tracking(2.4 * s)
                    .foregroundStyle(Color.recapLime)

                Text("Keep stacking climbs.")
                    .font(.montserratBold(size: 42 * s))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 12 * s)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12 * s
                ) {
                    ForEach(data.weeklyDisplayStats.prefix(4), id: \.label) { stat in
                        weeklyTile(stat, scale: s)
                    }
                }
                .padding(.top, 36 * s)

                VStack(alignment: .leading, spacing: 12 * s) {
                    Text("LATEST CLIMB")
                        .font(.montserratBold(size: 10 * s))
                        .tracking(2 * s)
                        .foregroundStyle(.white.opacity(0.42))

                    HStack(spacing: 14 * s) {
                        ClimbArtworkView(climb: data.climb, variant: .thumb)
                            .frame(width: 62 * s, height: 62 * s)
                            .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))

                        VStack(alignment: .leading, spacing: 4 * s) {
                            Text(data.climbName)
                                .font(.montserratBold(size: 17 * s))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(data.stepsText) steps · \(data.durationText)")
                                .font(.montserratMedium(size: 12 * s))
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(14 * s)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20 * s, style: .continuous))
                }
                .padding(.top, 34 * s)

                Spacer()

                AscendWordmark(size: 15 * s, letterColor: .white.opacity(0.94))
                    .frame(maxWidth: .infinity)
            }
            .padding(28 * s)
            .padding(.top, 42 * s)
            .padding(.bottom, 36 * s)
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func artworkBackground(overlay colors: [Color]) -> some View {
        ZStack {
            if let climbArtworkOverride {
                Image(uiImage: climbArtworkOverride)
                    .resizable()
                    .scaledToFill()
            } else {
                ClimbArtworkView(climb: data.climb, variant: .hero)
            }

            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }
    }

    private func chip(_ text: String, scale s: CGFloat) -> some View {
        Text(text)
            .font(.montserratBold(size: 9 * s))
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
                .font(.montserratBold(size: 22 * s))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(shortLabel(stat.label))
                .font(.montserratBold(size: 8 * s))
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
                .font(.montserratBold(size: 15 * s))
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
        .font(.montserratBold(size: 9 * s))
        .tracking(1.6 * s)
        .foregroundStyle(.white.opacity(0.64))
    }

    private func splitRow(_ row: ResolvedShareSplitRow, scale s: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12 * s) {
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(row.segmentText)
                    .font(.montserratBold(size: 21 * s))
                    .foregroundStyle(.white)
                Text(row.rangeText)
                    .font(.montserratBold(size: 8 * s))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(width: 48 * s, alignment: .leading)

            Text(row.spmText)
                .font(.montserratBold(size: 20 * s))
                .foregroundStyle(.white)
                .frame(width: 38 * s, alignment: .leading)

            splitProgressBar(progress: row.progress, scale: s)

            Text(row.stepsText)
                .font(.montserratBold(size: 17 * s))
                .foregroundStyle(.white)
                .frame(width: 58 * s, alignment: .trailing)

            Text(row.heartRateText ?? "--")
                .font(.montserratBold(size: 17 * s))
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
                .font(.montserratBold(size: 8 * s))
                .tracking(1.4 * s)
                .foregroundStyle(.black.opacity(0.46))
            Text(value)
                .font(.montserratBold(size: 20 * s))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12 * s)
        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
    }

    private func podiumRow(place: String, name: String, value: String, highlighted: Bool, scale s: CGFloat) -> some View {
        HStack(spacing: 12 * s) {
            Text(place)
                .font(.montserratBold(size: 18 * s))
                .foregroundStyle(highlighted ? .black : .white.opacity(0.7))
                .frame(width: 42 * s, height: 42 * s)
                .background(highlighted ? Color.recapLime : Color.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(name)
                    .font(.montserratBold(size: 15 * s))
                    .foregroundStyle(.white)
                Text(value)
                    .font(.montserratBold(size: 11 * s))
                    .tracking(1.2 * s)
                    .foregroundStyle(highlighted ? Color.recapLime : .white.opacity(0.46))
            }
            Spacer()
        }
        .padding(12 * s)
        .background(Color.white.opacity(highlighted ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
    }

    private func glassMetric(_ label: String, _ value: String, progress: Double, scale s: CGFloat) -> some View {
        HStack(spacing: 12 * s) {
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(shortLabel(label))
                    .font(.montserratBold(size: 8 * s))
                    .tracking(1.5 * s)
                    .foregroundStyle(.white.opacity(0.48))
                Text(value)
                    .font(.montserratBold(size: 20 * s))
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

    private func wrappedMetric(rank: String, label: String, value: String, scale s: CGFloat) -> some View {
        HStack {
            Text(rank)
                .font(.montserratBold(size: 12 * s))
                .foregroundStyle(Color.recapLime)
                .frame(width: 34 * s, height: 34 * s)
                .background(.black, in: Circle())
            Text(label)
                .font(.montserratBold(size: 11 * s))
                .tracking(1.8 * s)
                .foregroundStyle(.white.opacity(0.62))
            Spacer()
            Text(value)
                .font(.montserratBold(size: 22 * s))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(15 * s)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 18 * s, style: .continuous))
    }

    private func blueprintMetric(_ label: String, _ value: String, scale s: CGFloat) -> some View {
        HStack {
            Text(label)
                .font(.montserratBold(size: 9 * s))
                .tracking(1.8 * s)
                .foregroundStyle(Color.recapLime)
            Spacer()
            Text(value)
                .font(.montserratBold(size: 18 * s))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 12 * s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.recapLime.opacity(0.18)).frame(height: 1)
        }
    }

    private func weeklyTile(_ stat: ResolvedShareStat, scale s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text(stat.value)
                .font(.montserratBold(size: 26 * s))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(shortLabel(stat.label))
                .font(.montserratBold(size: 8 * s))
                .tracking(1.4 * s)
                .foregroundStyle(Color.recapLime)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16 * s)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18 * s, style: .continuous))
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

private struct MountainMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX * 0.58, y: rect.midY * 0.86))
        path.addLine(to: CGPoint(x: rect.midX * 0.92, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX * 1.14, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX * 1.45, y: rect.midY * 0.96))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private func mountainMark(scale: CGFloat) -> MountainMark {
    MountainMark()
}

private func blueprintGrid(scale s: CGFloat) -> Path {
    Path { path in
        let width = 390 * s
        let height = 693 * s
        let step = 28 * s
        stride(from: 0, through: width, by: step).forEach { x in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        stride(from: 0, through: height, by: step).forEach { y in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
    }
}

private extension Array where Element == ResolvedShareStat {
    func uniquedByLabel() -> [ResolvedShareStat] {
        var seen = Set<String>()
        return filter { seen.insert($0.label).inserted }
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
