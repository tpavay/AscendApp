//
//  ProgressSheet.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI

struct ProgressSheet: View {
    let workouts: [Workout]
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var selectedDate = Date()
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var currentStreak: Int {
        Workout.calculateCurrentStreak(from: workouts)
    }
    
    private var weeklyStreak: Int {
        Workout.calculateWeeklyStreak(from: workouts)
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

    private var totalStepsThisMonth: Int {
        currentMonthWorkouts.compactMap(\.steps).reduce(0, +)
    }

    private var totalCaloriesThisMonth: Int {
        currentMonthWorkouts.compactMap(\.caloriesBurned).reduce(0, +)
    }

    private var totalDurationThisMonth: TimeInterval {
        currentMonthWorkouts.map(\.duration).reduce(0, +)
    }

    private var averageStepsPerMinuteThisMonth: Double {
        let totalMinutes = totalDurationThisMonth / 60
        guard totalMinutes > 0 else { return 0 }
        return Double(totalStepsThisMonth) / totalMinutes
    }

    // MARK: - Best Efforts
    private var allBestEfforts: [BestEffort] {
        BestEffortsBuilder.bestEfforts(from: workouts)
    }
    
    private var recentBestEfforts: [BestEffort] {
        Array(allBestEfforts.prefix(3))
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

            // Best Efforts below calendar
            if !recentBestEfforts.isEmpty {
                bestEffortsPreviewSection
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .themedBackground()
    }

    private var bestEffortsPreviewSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Best Efforts")
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Spacer()
                
                NavigationLink {
                    BestEffortsListView(workouts: workouts)
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.montserratMedium(size: 14))
                            .foregroundStyle(.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.accent)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            VStack(spacing: 10) {
                ForEach(recentBestEfforts) { effort in
                    BestEffortRow(effort: effort, colorScheme: effectiveColorScheme)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    
    private var calendarSection: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
                
                Spacer()
                
                Text(monthYearFormatter.string(from: selectedDate))
                    .font(.montserratBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
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
            
            // Calendar days
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(calendarDays, id: \.date) { dayData in
                    calendarDay(dayData)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var monthSummary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                summaryItem(title: "Workouts", value: "\(totalWorkoutsThisMonth)")
                summaryItem(title: "Steps", value: formattedNumber(totalStepsThisMonth))
                summaryItem(title: "Calories", value: formattedNumber(totalCaloriesThisMonth))
            }
            
            HStack(spacing: 12) {
                summaryItem(title: "Duration", value: formattedDuration(totalDurationThisMonth))
                summaryItem(title: "Steps / Min", value: formattedStepsPerMinute(averageStepsPerMinuteThisMonth))
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var weeklyStreakView: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [.yellow, .orange, .red]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("WEEK STREAK")
                        .font(.montserratBold(size: 14))
                        .tracking(1.5)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.yellow, .orange]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Spacer()
                    
                    Text("\(weeklyStreak)")
                        .font(.montserratBold(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.yellow, .orange]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text("Weeks in a row you worked out at least once")
                    .font(.montserratSemiBold(size: 10))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(dayData.hasWorkout ?
                              AnyShapeStyle(LinearGradient(
                                gradient: Gradient(colors: [.yellow, .orange]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )) :
                              AnyShapeStyle(effectiveColorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                        )
                        .frame(height: 44)
                    
                    Text("\(dayData.day)")
                        .font(.montserratBold(size: 16))
                        .foregroundStyle(dayData.hasWorkout ? .white : (effectiveColorScheme == .dark ? .white : .black))
                }
            } else {
                Color.clear
                    .frame(height: 44)
            }
        }
    }

    // MARK: - Best Effort Row
    private struct BestEffortRow: View {
        let effort: BestEffort
        let colorScheme: ColorScheme
        
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: effort.iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.accent)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(effort.title)
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text(effort.detailText)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(effort.valueText)
                    .font(.montserratBold(size: 14))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.trailing)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
            )
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
            return String(format: "%d hr %02d min", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }

    private func formattedStepsPerMinute(_ value: Double) -> String {
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
            let hasWorkout = workoutDates.contains(calendar.startOfDay(for: currentDate))
            
            days.append(CalendarDay(
                date: currentDate,
                day: dayOfMonth,
                isCurrentMonth: isCurrentMonth,
                hasWorkout: hasWorkout
            ))
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
    
    private func previousMonth() {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        }
    }
    
    private func nextMonth() {
        withAnimation(.easeInOut(duration: 0.3)) {
            let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
            let currentMonth = Date()
            
            // Only allow navigation if the next month is not in the future
            if calendar.compare(nextMonthDate, to: currentMonth, toGranularity: .month) != .orderedDescending {
                selectedDate = nextMonthDate
            }
        }
    }
}

// MARK: - Supporting Data Structures
struct CalendarDay {
    let date: Date
    let day: Int
    let isCurrentMonth: Bool
    let hasWorkout: Bool
}

#Preview {
    let sampleWorkouts = [
        Workout(name: "Morning Workout", date: Date(), duration: 1800, steps: 2500),
        Workout(name: "Yesterday", date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, duration: 1200, steps: 1500),
        Workout(name: "Two days ago", date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, duration: 2000, steps: 2000),
        Workout(name: "Week ago", date: Calendar.current.date(byAdding: .day, value: -7, to: Date())!, duration: 1500, steps: 1800)
    ]
    
    ProgressSheet(workouts: sampleWorkouts)
}

#Preview("Dark Mode") {
    let sampleWorkouts = [
        Workout(name: "Morning Workout", date: Date(), duration: 1800, steps: 2500),
        Workout(name: "Yesterday", date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, duration: 1200, steps: 1500),
        Workout(name: "Two days ago", date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, duration: 2000, steps: 2000)
    ]
    
    ProgressSheet(workouts: sampleWorkouts)
        .preferredColorScheme(.dark)
}
