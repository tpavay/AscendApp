//
//  ProgressSheet.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftData
import SwiftUI

struct ProgressSheet: View {
    let workouts: [Workout]

    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \BestEffortCacheEntry.sortKey) private var bestEffortCacheEntries: [BestEffortCacheEntry]
    @State private var themeManager = ThemeManager.shared
    @State private var settingsManager = SettingsManager.shared
    @State private var selectedDate = Date()
    @State private var showIntensityExplanation = false
    @State private var selectedCalendarDay: CalendarDay?
    @State private var workoutToEdit: Workout?
    @State private var selectedHeatMapMetric: HeatMapMetric = .effortScore
    @State private var showMoreMetrics = false
    @State private var heatMapAnimationID = UUID()
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var currentStreak: Int {
        Workout.calculateCurrentStreak(from: workouts)
    }
    
    private var weeklyStreak: Int {
        Workout.calculateWeeklyStreak(from: workouts)
    }
    
    private var longestWeeklyStreak: Int {
        Workout.calculateLongestWeeklyStreak(from: workouts)
    }
    
    private var calendar: Calendar {
        Calendar.current
    }
    
    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter
    }
    
    private var workoutDates: Set<Date> {
        Set(workouts.map { calendar.startOfDay(for: $0.date) })
    }
    
    private var canGoToNextMonth: Bool {
        let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        let currentMonth = Date()
        return calendar.compare(nextMonthDate, to: currentMonth, toGranularity: .month) != .orderedDescending
    }

    // MARK: - Monthly Aggregates
    private var currentMonthWorkouts: [Workout] {
        workouts.filter { calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }
    }

    private var totalWorkoutsThisMonth: Int {
        currentMonthWorkouts.count
    }

    private var preferredMetric: WorkoutMetric {
        settingsManager.preferredWorkoutMetric
    }

    private var totalMetricValueThisMonth: Int {
        currentMonthWorkouts.reduce(0) { $0 + $1.metricValue(for: preferredMetric) }
    }

    private var totalCaloriesThisMonth: Int {
        currentMonthWorkouts.compactMap(\.caloriesBurned).reduce(0, +)
    }

    private var totalDurationThisMonth: TimeInterval {
        currentMonthWorkouts.map(\.duration).reduce(0, +)
    }

    private var averageMetricPerMinuteThisMonth: Double {
        let totalMinutes = totalDurationThisMonth / 60
        guard totalMinutes > 0 else { return 0 }
        return Double(totalMetricValueThisMonth) / totalMinutes
    }

    // MARK: - Best Efforts
    private var cacheSnapshot: BestEffortCacheSnapshot {
        BestEffortCacheSnapshot(entries: bestEffortCacheEntries, workouts: workouts)
    }

    private var bestEffortBoard: BestEffortBoard {
        cacheSnapshot.board(
            scope: .allTime,
            context: .all
        )
    }

    private var featuredBestEffort: RankedBestEffort? {
        bestEffortBoard.allEfforts.sorted { lhs, rhs in
            if lhs.workout.date != rhs.workout.date {
                return lhs.workout.date > rhs.workout.date
            }

            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }

            return lhs.id < rhs.id
        }
        .first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
            // Title
            HStack {
                Text("Progress")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            // Weekly streak hero (primary streak metric)
            weeklyStreakView
                .padding(.horizontal, 24)
                .padding(.top, 24)

            // Calendar section
            calendarSection
                .padding(.top, 24)

            // Monthly trends card
            WorkoutTrendsCard(
                workouts: workouts,
                selectedDate: selectedDate
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // Best Efforts below calendar
            bestEffortsPreviewSection
                .padding(.horizontal, 24)
                .padding(.top, 24)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
        .sheet(isPresented: $showIntensityExplanation) {
            IntensityExplanationView()
        }
        .sheet(item: $workoutToEdit) { workout in
            EditWorkoutView(workout: workout, showingEditWorkout: Binding(
                get: { workoutToEdit != nil },
                set: { isShowing in
                    if !isShowing {
                        workoutToEdit = nil
                    }
                }
            ))
        }
    }

    private var bestEffortsPreviewSection: some View {
        Group {
            if let featuredBestEffort {
                NavigationLink {
                    BestEffortsListView(workouts: workouts)
                } label: {
                    FeaturedBestEffortCard(
                        effort: featuredBestEffort,
                        colorScheme: effectiveColorScheme
                    )
                }
                .buttonStyle(.plain)
            } else {
                bestEffortsEmptyState
            }
        }
    }
    
    private var bestEffortsEmptyState: some View {
        VStack(spacing: 12) {
            AppIcon(token: .bestEffortTrophy, pointSize: 32, weight: .regular)
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.4))

            Text("No Best Efforts Yet")
                .font(.montserratSemiBold(size: 16))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)

            Text("Log or import workouts and come back here to see your top efforts for steps, duration, pace, and sampled intervals.")
                .font(.montserratRegular(size: 13))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var calendarSection: some View {
        VStack(spacing: 16) {
            // Month navigation with info button
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                Text(monthYearFormatter.string(from: selectedDate))
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    
                    Button {
                        showIntensityExplanation = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.accent)
                    }
                }
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(canGoToNextMonth ? (effectiveColorScheme == .dark ? .white : .black) : .gray.opacity(0.4))
                }
                .disabled(!canGoToNextMonth)
            }
            .padding(.horizontal, 24)
            
            // Calendar grid
            monthSummary
            calendarGrid
            
            // Selected day intensity details
            if let selectedDay = selectedCalendarDay, selectedDay.hasWorkout {
                workoutIntensityDetail(for: selectedDay)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 8) {
            // Day headers
            HStack {
                ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) { day in
                    Text(day)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)

            // Calendar days with heat map coloring
            // Animation type is easily swappable by changing the animation below
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(calendarDays, id: \.date) { dayData in
                    calendarDay(dayData)
                }
            }
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.4), value: heatMapAnimationID)
        }
    }
    
    private var monthSummary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                heatMapStatCard(
                    metric: .effortScore,
                    title: "Effort",
                    value: averageEffortScoreThisMonth
                )
                heatMapStatCard(
                    metric: .primaryMetric,
                    title: preferredMetric.displayName,
                    value: formattedNumber(totalMetricValueThisMonth)
                )
                heatMapStatCard(
                    metric: .calories,
                    title: "Calories",
                    value: formattedNumber(totalCaloriesThisMonth)
                )
            }

            HStack(spacing: 12) {
                heatMapStatCard(
                    metric: .duration,
                    title: "Duration",
                    value: formattedDuration(totalDurationThisMonth)
                )
                heatMapStatCard(
                    metric: .stepsPerMinute,
                    title: "\(preferredMetric.displayName) / Min",
                    value: formattedMetricPerMinute(averageMetricPerMinuteThisMonth)
                )
                moreMetricsButton
            }
        }
        .padding(.horizontal, 16)
    }

    private var averageEffortScoreThisMonth: String {
        guard !currentMonthWorkouts.isEmpty else { return "0.0" }
        let totalScore = currentMonthWorkouts.reduce(0.0) { sum, workout in
            sum + HeatMapScoreCalculator.score(for: workout, metric: .effortScore, using: settingsManager)
        }
        let average = totalScore / Double(currentMonthWorkouts.count)
        return (average * 10).formatted(.number.precision(.fractionLength(1))) // Display as 0.0-10.0
    }

    private func heatMapStatCard(metric: HeatMapMetric, title: String, value: String) -> some View {
        let isSelected = selectedHeatMapMetric == metric

        return Button {
            withAnimation(.easeInOut(duration: 0.4)) {
                selectedHeatMapMetric = metric
                heatMapAnimationID = UUID()
            }
            HapticsManager.shared.trigger(.lightImpact)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(isSelected ? .accent : (effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray))
                Text(value)
                    .font(.montserratBold(size: 18))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var moreMetricsButton: some View {
        Button {
            showMoreMetrics = true
            HapticsManager.shared.trigger(.lightImpact)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("MORE")
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(HeatMapMetric.moreMetrics.contains(selectedHeatMapMetric) ? .accent : (effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray))
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(HeatMapMetric.moreMetrics.contains(selectedHeatMapMetric) ? Color.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMoreMetrics) {
            moreMetricsSheet
                .appSheetStyle(.dialog(height: 300))
        }
    }

    private var moreMetricsSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ForEach(HeatMapMetric.moreMetrics) { metric in
                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            selectedHeatMapMetric = metric
                            heatMapAnimationID = UUID()
                        }
                        showMoreMetrics = false
                        HapticsManager.shared.trigger(.lightImpact)
                    } label: {
                        HStack {
                            Image(systemName: metric.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(selectedHeatMapMetric == metric ? .accent : .gray)
                                .frame(width: 32)

                            Text(metric.displayName)
                                .font(.montserratMedium(size: 16))
                                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)

                            Spacer()

                            if selectedHeatMapMetric == metric {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.accent)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedHeatMapMetric == metric ?
                                    (effectiveColorScheme == .dark ? Color.accent.opacity(0.15) : Color.accent.opacity(0.1)) :
                                    (effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(20)
            .background(effectiveColorScheme == .dark ? Color.jet : Color.white)
            .navigationTitle("Heat Map Metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showMoreMetrics = false
                    }
                    .foregroundStyle(.accent)
                }
            }
        }
    }
    
    private var weeklyStreakView: some View {
        HStack(spacing: 12) {
            // Current Week Streak Card
            streakCard(
                icon: "flame.fill",
                title: "WEEK STREAK",
                value: weeklyStreak,
                subtitle: "Current streak",
                gradientColors: [.yellow, .orange, .red]
            )
            
            // Longest Week Streak Card
            streakCard(
                icon: "trophy.fill",
                title: "BEST WEEKS",
                value: longestWeeklyStreak,
                subtitle: "Longest streak",
                gradientColors: [.purple, .pink, .orange]
            )
        }
    }
    
    private func streakCard(icon: String, title: String, value: Int, subtitle: String, gradientColors: [Color]) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Spacer()
                
                Text("\(value)")
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: Array(gradientColors.prefix(2))),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.montserratBold(size: 11))
                    .tracking(1)
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: Array(gradientColors.prefix(2))),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(subtitle)
                    .font(.montserratMedium(size: 10))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.12) : .gray.opacity(0.18), lineWidth: 1)
                )
        )
    }
    
    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.montserratMedium(size: 11))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
            Text(value)
                .font(.montserratBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
        )
    }
    
    private func calendarDay(_ dayData: CalendarDay) -> some View {
        Group {
            if dayData.isCurrentMonth {
                Button {
                    if dayData.hasWorkout {
                        HapticsManager.shared.trigger(.lightImpact)
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if dayData.hasWorkout {
                            // Toggle selection
                            if selectedCalendarDay?.date == dayData.date {
                                selectedCalendarDay = nil
                            } else {
                                selectedCalendarDay = dayData
                            }
                        }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(dayData.hasWorkout ?
                                      AnyShapeStyle(dayData.heatMapGradient(for: selectedHeatMapMetric, colorScheme: effectiveColorScheme)) :
                                  AnyShapeStyle(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                            )
                            .frame(height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedCalendarDay?.date == dayData.date ? Color.white : Color.clear, lineWidth: 3)
                            )

                        Text("\(dayData.day)")
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(dayData.hasWorkout ? .white : (effectiveColorScheme == .dark ? .white : .black))
                    }
                    .id("\(dayData.date)-\(heatMapAnimationID)")
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Color.clear
                    .frame(height: 44)
            }
        }
    }

    // MARK: - Featured Best Effort Card
    private struct FeaturedBestEffortCard: View {
        let effort: RankedBestEffort
        let colorScheme: ColorScheme

        var body: some View {
            ZStack(alignment: .trailing) {
                background

                Image("best-effort-laurel-wreath")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 246, height: 164)
                    .opacity(colorScheme == .dark ? 0.34 : 0.24)
                    .offset(x: 72, y: 0)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Best Efforts")
                        .font(.montserratBold(size: 22))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(heroValue)
                            .font(.montserratBold(size: 56))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)

                        Text(metricTitle)
                            .font(.montserratBold(size: 13))
                            .tracking(1.1)
                            .foregroundStyle(gold)
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        Text(effort.dateText)
                            .font(.montserratRegular(size: 12))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
            .frame(minHeight: 188)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderGradient, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.1), radius: 18, x: 0, y: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Best Efforts, \(metricTitle), \(effort.valueText), \(effort.dateText)")
        }

        private var background: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black)

                LinearGradient(
                    colors: [
                        Color.black,
                        Color.black.opacity(0.94),
                        gold.opacity(0.24)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                RadialGradient(
                    colors: [
                        gold.opacity(0.24),
                        Color.clear
                    ],
                    center: .trailing,
                    startRadius: 0,
                    endRadius: 230
                )
            }
        }

        private var heroValue: String {
            switch effort.metric {
            case .mostSteps, .mostStepsInTime, .highestAverageSPM:
                return effort.compactValueText
            case .longestClimb, .fastestStepTarget:
                return BestEffortFormatting.clockTime(effort.performance.value)
            }
        }

        private var metricTitle: String {
            switch effort.metric {
            case .highestAverageSPM:
                return "Highest Avg. SPM"
            case .mostSteps, .longestClimb, .mostStepsInTime, .fastestStepTarget:
                return effort.metric.title
            }
        }

        private var borderGradient: LinearGradient {
            LinearGradient(
                colors: [
                    gold.opacity(0.64),
                    Color.white.opacity(0.1),
                    gold.opacity(0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        private var gold: Color {
            BestEffortUIStyle.trophyColor(for: 1)
        }
    }
    
    private var bottomSection: some View {
        VStack(spacing: 16) {
            // Sample achievement badges row
            HStack(spacing: 20) {
                ForEach([
                    ("Invested", Color.orange),
                    ("Steadfast", Color.gray),
                    ("Radiant", Color.yellow)
                ], id: \.0) { name, color in
                    VStack(spacing: 8) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [color, color.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: name == "Invested" ? "star.fill" : name == "Steadfast" ? "star.circle.fill" : "crown.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                        
                        Text(name)
                            .font(.montserratMedium(size: 12))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            // Progress indicator (placeholder for now)
            HStack {
                Rectangle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [.yellow, .orange]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(height: 4)
                    .frame(width: 120)
                    .clipShape(Capsule())
                
                Rectangle()
                    .fill(effectiveColorScheme == .dark ? .white.opacity(0.2) : .gray.opacity(0.3))
                    .frame(height: 4)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 60)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Formatting Helpers
    private func formattedNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours) hr \(minutes < 10 ? "0" : "")\(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }

    private func formattedMetricPerMinute(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
    
    // MARK: - Calendar Logic
    
    private var calendarDays: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else {
            return []
        }
        
        let firstOfMonth = monthInterval.start
        let lastOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: firstOfMonth)!
        
        // Get the first Sunday of the calendar grid
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let startDate = calendar.date(byAdding: .day, value: -(firstWeekday - 1), to: firstOfMonth)!
        
        // Get the last Saturday of the calendar grid
        let lastWeekday = calendar.component(.weekday, from: lastOfMonth)
        let endDate = calendar.date(byAdding: .day, value: (7 - lastWeekday), to: lastOfMonth)!
        
        var days: [CalendarDay] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            let dayOfMonth = calendar.component(.day, from: currentDate)
            let isCurrentMonth = calendar.isDate(currentDate, equalTo: selectedDate, toGranularity: .month)

            // Get all workouts for this day
            let workoutsForDay = workouts.filter { calendar.isDate($0.date, inSameDayAs: currentDate) }
            
            days.append(CalendarDay(
                date: currentDate,
                day: dayOfMonth,
                isCurrentMonth: isCurrentMonth,
                workouts: workoutsForDay
            ))
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func previousMonth() {
        HapticsManager.shared.trigger(.lightImpact)
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
            selectedCalendarDay = nil
        }
    }
    
    private func nextMonth() {
        let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        let currentMonth = Date()
        
        // Only allow navigation if the next month is not in the future
        if calendar.compare(nextMonthDate, to: currentMonth, toGranularity: .month) != .orderedDescending {
            HapticsManager.shared.trigger(.lightImpact)
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedDate = nextMonthDate
                selectedCalendarDay = nil
            }
        }
    }
    
    // MARK: - Workout Intensity Detail
    
    private func workoutIntensityDetail(for day: CalendarDay) -> some View {
        VStack(spacing: 16) {
            // Header with metric name and close button
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: selectedHeatMapMetric.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.accent)

                    Text(selectedHeatMapMetric.displayName)
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedCalendarDay = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.5) : .gray)
                }
            }

            // Workout cards with metric value
            ForEach(day.workouts, id: \.id) { workout in
                workoutMetricCard(workout: workout)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.15) : .gray.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func workoutMetricCard(workout: Workout) -> some View {
        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
            HStack(spacing: 12) {
                // Metric value badge with gradient
                let score = HeatMapScoreCalculator.score(for: workout, metric: selectedHeatMapMetric, using: settingsManager)
                let displayValue = HeatMapScoreCalculator.displayValue(for: workout, metric: selectedHeatMapMetric, using: settingsManager)
                let unitSuffix = HeatMapScoreCalculator.unitSuffix(for: selectedHeatMapMetric, using: settingsManager)

                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.heatMapGradient(for: score, colorScheme: effectiveColorScheme))
                        .frame(width: 56, height: 56)

                    VStack(spacing: 0) {
                        Text(displayValue)
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(.white)
                        if !unitSuffix.trimmingCharacters(in: .whitespaces).isEmpty && selectedHeatMapMetric != .duration {
                            Text(unitSuffix.trimmingCharacters(in: .whitespaces))
                                .font(.montserratMedium(size: 9))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }

                // Workout info
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    Text(workout.date.formatted(date: .omitted, time: .shortened))
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.4) : .gray)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(effectiveColorScheme == .dark ? .white.opacity(0.05) : .white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Supporting Data Structures
struct CalendarDay {
    let date: Date
    let day: Int
    let isCurrentMonth: Bool
    let workouts: [Workout]

    var hasWorkout: Bool {
        !workouts.isEmpty
    }

    /// Calculate the heat map score for this day based on the selected metric
    /// Returns nil if no workouts, otherwise returns the highest score (0.0 to 1.0)
    @MainActor
    func heatMapScore(for metric: HeatMapMetric, using settings: SettingsManager = .shared) -> Double? {
        HeatMapScoreCalculator.score(for: workouts, metric: metric, using: settings)
    }

    /// Get the heat map gradient for this day based on the selected metric
    @MainActor
    func heatMapGradient(for metric: HeatMapMetric, colorScheme: ColorScheme, using settings: SettingsManager = .shared) -> LinearGradient {
        guard let score = heatMapScore(for: metric, using: settings) else {
            return LinearGradient(
                gradient: Gradient(colors: [.gray.opacity(0.3), .gray.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return Color.heatMapGradient(for: score, colorScheme: colorScheme)
    }

    /// Get the display value for this day's metric (shows highest value if multiple workouts)
    @MainActor
    func metricDisplayValue(for metric: HeatMapMetric, using settings: SettingsManager = .shared) -> String? {
        guard !workouts.isEmpty else { return nil }

        // Find the workout with the highest score for this metric
        let workoutWithHighestScore = workouts.max { workout1, workout2 in
            let score1 = HeatMapScoreCalculator.score(for: workout1, metric: metric, using: settings)
            let score2 = HeatMapScoreCalculator.score(for: workout2, metric: metric, using: settings)
            return score1 < score2
        }

        guard let workout = workoutWithHighestScore else { return nil }
        return HeatMapScoreCalculator.displayValue(for: workout, metric: metric, using: settings)
    }
}

#Preview {
    let sampleWorkouts = [
        Workout(name: "Morning Workout", date: Date(), duration: 1800, steps: 2500, floors: 156, stepsPerFloor: 16),
        Workout(name: "Yesterday", date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, duration: 1200, steps: 1500, floors: 94, stepsPerFloor: 16),
        Workout(name: "Two days ago", date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, duration: 2000, steps: 2000, floors: 125, stepsPerFloor: 16),
        Workout(name: "Week ago", date: Calendar.current.date(byAdding: .day, value: -7, to: Date())!, duration: 1500, steps: 1800, floors: 113, stepsPerFloor: 16)
    ]

    ProgressSheet(workouts: sampleWorkouts)
        .modelContainer(for: [Workout.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self], inMemory: true)
}

#Preview("Dark Mode") {
    let sampleWorkouts = [
        Workout(name: "Morning Workout", date: Date(), duration: 1800, steps: 2500, floors: 156, stepsPerFloor: 16),
        Workout(name: "Yesterday", date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, duration: 1200, steps: 1500, floors: 94, stepsPerFloor: 16),
        Workout(name: "Two days ago", date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, duration: 2000, steps: 2000, floors: 125, stepsPerFloor: 16)
    ]

    ProgressSheet(workouts: sampleWorkouts)
        .preferredColorScheme(.dark)
        .modelContainer(for: [Workout.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self], inMemory: true)
}
