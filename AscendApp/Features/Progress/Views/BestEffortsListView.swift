//
//  BestEffortsListView.swift
//  AscendApp
//
//  Created by GPT-5.1 on 11/20/25.
//

import SwiftData
import SwiftUI

struct BestEffortsListView: View {
    let workouts: [Workout]

    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var themeManager = ThemeManager.shared

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var cacheSnapshot: BestEffortCacheSnapshot {
        BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: workouts)
    }

    private var board: BestEffortBoard {
        cacheSnapshot.board(
            scope: .allTime,
            context: .all
        )
    }

    private var categories: [BestEffortCategoryRanking] {
        BestEffortMetric.allDefinitions
            .compactMap { board.category($0) }
            .sorted { lhs, rhs in
                lhs.metric.displayPriority < rhs.metric.displayPriority
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if categories.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(categories) { category in
                            NavigationLink {
                                BestEffortRecordDetailView(
                                    metric: category.metric,
                                    workouts: workouts
                                )
                            } label: {
                                BestEffortOverviewRow(
                                    category: category,
                                    colorScheme: effectiveColorScheme
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 124)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationTitle("Best Efforts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            AppIcon(token: .bestEffortTrophy, pointSize: 34, weight: .medium)
                .foregroundStyle(foregroundSubtle)

            Text("No Best Efforts Yet")
                .font(.montserratBold(size: 18))
                .foregroundStyle(foregroundPrimary)
                .multilineTextAlignment(.center)

            Text("Log, import, or complete workouts to start building your record book.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(foregroundSubtle)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var foregroundPrimary: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var foregroundSubtle: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.52)
    }

    private var cardFill: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.035)
    }

    private var cardStroke: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.07)
    }
}

private struct BestEffortOverviewRow: View {
    let category: BestEffortCategoryRanking
    let colorScheme: ColorScheme

    private var topEffort: RankedBestEffort? {
        category.efforts.first
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(rowTitle)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(foregroundPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let topEffort {
                    Text(topEffort.dateText)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(foregroundSubtle)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            if let topEffort {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(rowValue(for: topEffort))
                        .font(.montserratBold(size: 17))
                        .foregroundStyle(foregroundPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if category.metric.requiresTimeline {
                        Text("Live Climb")
                            .font(.montserratMedium(size: 10))
                            .foregroundStyle(foregroundSubtle)
                    }
                }
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let topEffort else { return category.metric.title }
        return "\(category.metric.title), \(topEffort.valueText), \(topEffort.dateText)"
    }

    private var rowTitle: String {
        switch category.metric {
        case .highestAverageSPM:
            return "Highest Avg. SPM"
        case .mostSteps, .longestClimb, .mostStepsInTime, .fastestStepTarget:
            return category.metric.title
        }
    }

    private func rowValue(for effort: RankedBestEffort) -> String {
        switch category.metric {
        case .mostSteps, .highestAverageSPM, .mostStepsInTime:
            return effort.compactValueText
        case .longestClimb, .fastestStepTarget:
            return BestEffortFormatting.clockTime(effort.performance.value)
        }
    }

    private var foregroundPrimary: Color {
        colorScheme == .dark ? .white : .black
    }

    private var foregroundSubtle: Color {
        colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.52)
    }

    private var cardFill: Color {
        colorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.035)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.07)
    }

}

struct BestEffortRecordDetailView: View {
    let metric: BestEffortMetric
    let workouts: [Workout]

    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var themeManager = ThemeManager.shared
    @State private var selectedMode: BestEffortRecordDetailMode = .chart

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var cacheSnapshot: BestEffortCacheSnapshot {
        BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: workouts)
    }

    private var rankedEfforts: [RankedBestEffort] {
        cacheSnapshot.rankedEfforts(
            for: metric,
            scope: .allTime,
            context: .all
        )
    }

    private var progressionEfforts: [RankedBestEffort] {
        cacheSnapshot.recordProgression(
            for: metric,
            scope: .allTime,
            context: .all
        )
    }

    private var topEffort: RankedBestEffort? {
        rankedEfforts.first
    }

    private var previousRecordEffort: RankedBestEffort? {
        guard progressionEfforts.count > 1 else { return nil }
        return progressionEfforts.dropLast().last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let topEffort {
                    BestEffortRecordHeroView(
                        effort: topEffort,
                        previousRecord: previousRecordEffort,
                        colorScheme: effectiveColorScheme
                    )

                    detailModePicker
                        .padding(.top, 8)

                    selectedContent
                } else {
                    emptyState
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 124)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailModePicker: some View {
        BestEffortDetailSegmentedControl(
            selection: $selectedMode,
            colorScheme: effectiveColorScheme
        )
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedMode {
        case .chart:
            BestEffortProgressionChart(
                metric: metric,
                efforts: progressionEfforts,
                colorScheme: effectiveColorScheme
            )
            .padding(.top, 4)
        case .history:
            BestEffortRecordHistoryView(
                efforts: progressionEfforts,
                colorScheme: effectiveColorScheme
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            AppIcon(token: .bestEffortTrophy, pointSize: 34, weight: .medium)
                .foregroundStyle(foregroundSubtle)

            Text("No \(metric.title) Yet")
                .font(.montserratBold(size: 18))
                .foregroundStyle(foregroundPrimary)
                .multilineTextAlignment(.center)

            Text(metric.requiresTimeline ? "Live Climb samples unlock this record." : "Log more workouts to start this record.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(foregroundSubtle)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var foregroundPrimary: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var foregroundSubtle: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.52)
    }

    private var cardFill: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.035)
    }

    private var cardStroke: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.07)
    }
}

private enum BestEffortRecordDetailMode: String, CaseIterable, Identifiable {
    case chart
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chart:
            return "Chart"
        case .history:
            return "History"
        }
    }

    var iconToken: AppIconToken {
        switch self {
        case .chart:
            return .bestEffortChartLine
        case .history:
            return .bestEffortClock
        }
    }
}

private struct BestEffortDetailSegmentedControl: View {
    @Binding var selection: BestEffortRecordDetailMode
    let colorScheme: ColorScheme

    private var selectedIndex: Int {
        BestEffortRecordDetailMode.allCases.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(BestEffortRecordDetailMode.allCases.enumerated()), id: \.element.id) { index, mode in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 8) {
                        AppIcon(token: mode.iconToken, pointSize: 20, weight: .semibold)

                        Text(mode.title.uppercased())
                            .font(.montserratBold(size: 12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == mode ? selectedForeground : unselectedForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])

                if index < BestEffortRecordDetailMode.allCases.count - 1 {
                    Rectangle()
                        .fill(dividerFill)
                        .frame(width: 1, height: 24)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(controlFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(controlStroke, lineWidth: 1)
        )
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                let segmentWidth = proxy.size.width / CGFloat(BestEffortRecordDetailMode.allCases.count)

                Rectangle()
                    .fill(selectedUnderline)
                    .frame(width: segmentWidth * 0.74, height: 2)
                    .offset(x: CGFloat(selectedIndex) * segmentWidth + segmentWidth * 0.13, y: proxy.size.height - 2)
            }
            .allowsHitTesting(false)
        }
        .shadow(color: Color.accentColor.opacity(colorScheme == .dark ? 0.06 : 0.03), radius: 10, x: 0, y: 5)
    }

    private var selectedForeground: Color {
        Color.accentColor
    }

    private var unselectedForeground: Color {
        colorScheme == .dark ? .white.opacity(0.48) : .black.opacity(0.46)
    }

    private var controlFill: Color {
        colorScheme == .dark ? .black.opacity(0.24) : .white.opacity(0.42)
    }

    private var controlStroke: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.1)
    }

    private var dividerFill: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.12)
    }

    private var selectedUnderline: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.45),
                Color.accentColor,
                Color.accentColor.opacity(0.45)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct BestEffortRecordHeroView: View {
    let effort: RankedBestEffort
    let previousRecord: RankedBestEffort?
    let colorScheme: ColorScheme

    private let gold = Color(red: 0.92, green: 0.68, blue: 0.22)
    private let lightGold = Color(red: 1.0, green: 0.86, blue: 0.46)

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let wreathWidth = min(proxy.size.width + 120, 460)

                ZStack {
                    Image("best-effort-laurel-wreath")
                        .resizable()
                        .scaledToFit()
                        .frame(width: wreathWidth, height: wreathWidth * 0.67)
                        .opacity(0.96)
                        .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text(effort.metric.title.uppercased())
                            .font(.montserratMedium(size: 14))
                            .kerning(metricTitleKerning)
                            .foregroundStyle(metricTitleGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.56)
                            .frame(width: min(wreathWidth * 0.74, 320), alignment: .center)

                        Text(heroValue)
                            .font(.montserratBold(size: 72))
                            .foregroundStyle(valueGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .frame(width: min(wreathWidth * 0.72, 330), alignment: .center)
                            .shadow(color: gold.opacity(0.38), radius: 12, x: 0, y: 0)
                    }
                    .offset(y: -36)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 224)

            VStack(spacing: 8) {
                if let comparisonText {
                    Text(comparisonText)
                        .font(.montserratBold(size: 12))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                HStack(spacing: 8) {
                    Text(recordDateText)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: 4)

                    Text(effort.workout.name)
                }
                .font(.montserratRegular(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(effort.metric.title), \(effort.valueText), \(effort.dateText)")
    }

    private var valueGradient: LinearGradient {
        LinearGradient(
            colors: [
                lightGold,
                gold,
                Color(red: 0.62, green: 0.41, blue: 0.09)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var metricTitleGradient: LinearGradient {
        LinearGradient(
            colors: [
                lightGold.opacity(0.96),
                gold.opacity(0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var metricTitleKerning: CGFloat {
        effort.metric.title.count > 14 ? 3.5 : 7
    }

    private var heroValue: String {
        switch effort.metric {
        case .mostSteps, .mostStepsInTime, .highestAverageSPM:
            return effort.compactValueText
        case .longestClimb, .fastestStepTarget:
            return BestEffortFormatting.clockTime(effort.performance.value)
        }
    }

    private var comparisonText: String? {
        guard let previousRecord else { return nil }
        let delta = abs(previousRecord.performance.value - effort.performance.value)
        guard delta > 0 else { return nil }

        switch effort.metric.comparisonDirection {
        case .higherIsBetter:
            return "+\(BestEffortDisplay.deltaText(delta, metric: effort.metric)) over previous record"
        case .lowerIsBetter:
            return "-\(BestEffortDisplay.deltaText(delta, metric: effort.metric)) over previous record"
        }
    }

    private var recordDateText: String {
        effort.workout.date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private struct BestEffortProgressionChart: View {
    let metric: BestEffortMetric
    let efforts: [RankedBestEffort]
    let colorScheme: ColorScheme

    var body: some View {
        ProgressLineChartView(
            title: metric.title,
            points: chartPoints,
            colorScheme: colorScheme,
            xAxisStyle: .monthYear,
            emptyText: "No progression data yet.",
            yAxisLabel: { BestEffortDisplay.axisLabel($0, metric: metric) }
        )
    }

    private var chartPoints: [ProgressLineChartPoint] {
        efforts.map { effort in
            ProgressLineChartPoint(
                id: effort.id,
                date: effort.workout.date,
                value: effort.performance.value,
                valueText: chartValueText(for: effort),
                dateText: effort.workout.date.formatted(.dateTime.month(.abbreviated).day().year())
            )
        }
    }

    private func chartValueText(for effort: RankedBestEffort) -> String {
        switch effort.metric {
        case .mostSteps, .highestAverageSPM, .mostStepsInTime:
            return effort.compactValueText
        case .longestClimb, .fastestStepTarget:
            return BestEffortFormatting.clockTime(effort.performance.value)
        }
    }
}

private struct BestEffortRecordHistoryView: View {
    let efforts: [RankedBestEffort]
    let colorScheme: ColorScheme

    private var previousEfforts: [RankedBestEffort] {
        Array(efforts.reversed().dropFirst())
    }

    var body: some View {
        Group {
            if previousEfforts.isEmpty {
                Text("No previous records yet.")
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(foregroundSubtle)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(previousEfforts.enumerated()), id: \.element.id) { index, effort in
                        NavigationLink {
                            WorkoutDetailView(workout: effort.workout)
                        } label: {
                            BestEffortRecordHistoryRow(
                                rank: index + 2,
                                effort: effort,
                                colorScheme: colorScheme
                            )
                        }
                        .buttonStyle(.plain)

                        if index < previousEfforts.count - 1 {
                            Divider()
                                .background(cardStroke)
                                .padding(.leading, 64)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
            }
        }
    }

    private var foregroundSubtle: Color {
        colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.52)
    }

    private var cardFill: Color {
        colorScheme == .dark ? .white.opacity(0.055) : .black.opacity(0.035)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.07)
    }
}

private struct BestEffortRecordHistoryRow: View {
    let rank: Int
    let effort: RankedBestEffort
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.montserratBold(size: 17))
                .foregroundStyle(rankColor)
                .frame(width: 34, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(effort.workout.name)
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(foregroundPrimary)
                    .lineLimit(1)

                Text(effort.dateText)
                    .font(.montserratRegular(size: 11))
                    .foregroundStyle(foregroundSubtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 10)

            Text(rowValue)
                .font(.montserratBold(size: 15))
                .foregroundStyle(foregroundPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Number \(rank), \(effort.workout.name), \(rowValue), \(effort.dateText)")
    }

    private var rowValue: String {
        switch effort.metric {
        case .mostSteps, .highestAverageSPM, .mostStepsInTime:
            return effort.compactValueText
        case .longestClimb, .fastestStepTarget:
            return BestEffortFormatting.clockTime(effort.performance.value)
        }
    }

    private var rankColor: Color {
        switch rank {
        case 2, 3:
            return BestEffortUIStyle.trophyColor(for: rank)
        default:
            return foregroundSubtle
        }
    }

    private var foregroundPrimary: Color {
        colorScheme == .dark ? .white : .black
    }

    private var foregroundSubtle: Color {
        colorScheme == .dark ? .white.opacity(0.56) : .black.opacity(0.52)
    }
}

private enum BestEffortDisplay {
    static func stepLabel(_ steps: Int) -> String {
        if steps >= 1_000 {
            let thousands = Double(steps) / 1_000
            if thousands.rounded() == thousands {
                return "\(Int(thousands))K"
            }
            return "\(thousands.formatted(.number.precision(.fractionLength(1))))K"
        }

        return BestEffortFormatting.integer(steps)
    }

    static func timeLabel(_ minutes: Int) -> String {
        if minutes == 60 {
            return "1 hour"
        }

        return "\(minutes) min"
    }

    static func unitText(for metric: BestEffortMetric) -> String? {
        switch metric {
        case .mostSteps, .mostStepsInTime:
            return "steps"
        case .highestAverageSPM:
            return "SPM"
        case .longestClimb, .fastestStepTarget:
            return nil
        }
    }

    static func deltaText(_ value: Double, metric: BestEffortMetric) -> String {
        switch metric {
        case .mostSteps, .mostStepsInTime:
            return "\(BestEffortFormatting.integer(Int(value.rounded()))) steps"
        case .longestClimb:
            return BestEffortFormatting.duration(value)
        case .highestAverageSPM:
            return "\(BestEffortFormatting.integer(Int(value.rounded()))) SPM"
        case .fastestStepTarget:
            return deltaDuration(value)
        }
    }

    static func axisLabel(_ value: Double, metric: BestEffortMetric) -> String {
        switch metric {
        case .mostSteps, .mostStepsInTime, .highestAverageSPM:
            return BestEffortFormatting.integer(Int(value.rounded()))
        case .longestClimb, .fastestStepTarget:
            return BestEffortFormatting.clockTime(value)
        }
    }

    static func deltaDuration(_ seconds: TimeInterval) -> String {
        let roundedSeconds = max(Int(seconds.rounded()), 0)
        if roundedSeconds < 60 {
            return "\(roundedSeconds) sec"
        }

        return BestEffortFormatting.clockTime(TimeInterval(roundedSeconds))
    }
}

private extension BestEffortBoard {
    func category(_ metric: BestEffortMetric) -> BestEffortCategoryRanking? {
        sections
            .flatMap(\.categories)
            .first { $0.metric == metric }
    }
}

#Preview {
    let sampleWorkouts = [
        Workout(
            name: "Morning Climb",
            date: Date(),
            duration: 45 * 60,
            steps: 5_200,
            floors: 325,
            stepsPerFloor: 16,
            avgHeartRate: 135,
            maxHeartRate: 168,
            caloriesBurned: 520,
            effortRating: 4.5,
            averageMETs: 7.2
        ),
        Workout(
            name: "Evening Session",
            date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            duration: 30 * 60,
            steps: 4_300,
            floors: 268,
            stepsPerFloor: 16,
            avgHeartRate: 128,
            maxHeartRate: 160,
            caloriesBurned: 430,
            effortRating: 3.8,
            averageMETs: 6.5
        )
    ]

    NavigationStack {
        BestEffortsListView(workouts: sampleWorkouts)
    }
    .modelContainer(for: [Workout.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self], inMemory: true)
}
