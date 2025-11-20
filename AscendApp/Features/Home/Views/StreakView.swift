//
//  StreakView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI
import SwiftData

struct DailyWorkoutNavigation: Hashable {
    let date: Date
    let workouts: [Workout]
}

struct StreakView: View {
    let workouts: [Workout]
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var tabRouter: TabRouter
    @State private var themeManager = ThemeManager.shared
    @State private var selectedWindowOffset: Int = 0 // 0 = last 7 days, -1 = previous 7 days, etc.
    @State private var selectedWorkout: Workout?
    @State private var selectedDailyWorkouts: DailyWorkoutNavigation?
    @State private var showWorkoutDetail = false
    @State private var showDailyWorkoutDetail = false
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var currentStreak: Int {
        Workout.calculateCurrentStreak(from: workouts)
    }
    
    private var sevenDayDateRange: String {
        let calendar = Calendar.current
        let range = sevenDayWindow(for: selectedWindowOffset)
        let startOfWindow = range.start
        let endOfWindow = range.end
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        let startString = formatter.string(from: startOfWindow)
        let endString = formatter.string(from: endOfWindow)
        let startYear = calendar.component(.year, from: startOfWindow)
        let endYear = calendar.component(.year, from: endOfWindow)
        
        if startYear == endYear {
            return "\(startString) - \(endString), \(startYear)"
        }
        
        let longFormatter = DateFormatter()
        longFormatter.dateFormat = "MMM d, yyyy"
        return "\(longFormatter.string(from: startOfWindow)) - \(longFormatter.string(from: endOfWindow))"
    }
    
    // Number of seven-day windows to show (current + past windows)
    private let numberOfWindows = 12
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with title and streak counter
            HStack {
                Text("Streak & Activity")
                    .font(.montserratSemiBold(size: 20))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                
                Spacer()
                
                // Streak counter - Tappable
                Button(action: {
                    tabRouter.selectedTab = .progress
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.orange)
                        
                        Text("\(currentStreak)")
                            .font(.montserratBold(size: 18))
                            .foregroundStyle(
                                currentStreak > 0 
                                    ? AnyShapeStyle(LinearGradient(
                                        gradient: Gradient(colors: [.yellow, .orange]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    : AnyShapeStyle(effectiveColorScheme == .dark ? .white.opacity(0.6) : .gray)
                            )
                        
                        Text(currentStreak == 1 ? "day" : "days")
                            .font(.montserratRegular(size: 16))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Weekly activity calendar with swipe navigation
            VStack(spacing: 12) {
                // Date range - updates based on selected window
                Text(sevenDayDateRange)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.8) : .gray)
                    .animation(.easeInOut(duration: 0.3), value: selectedWindowOffset)
                
                // Swipeable seven-day view
                TabView(selection: $selectedWindowOffset) {
                    ForEach((0...(numberOfWindows - 1)).reversed(), id: \.self) { windowOffset in
                        sevenDayView(for: -windowOffset) // Negative offset for past windows
                            .tag(-windowOffset)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(height: 80)
                .animation(.easeInOut(duration: 0.3), value: selectedWindowOffset)
                .onChange(of: selectedWindowOffset) { oldValue, newValue in
                    // Prevent swiping into the future (positive offsets)
                    if newValue > 0 {
                        selectedWindowOffset = 0
                    }
                }
                
                // Window indicator dots
                HStack(spacing: 6) {
                    ForEach((0...(numberOfWindows - 1)).reversed(), id: \.self) { windowOffset in
                        Circle()
                            .fill(selectedWindowOffset == -windowOffset ? .accent : (effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.4)))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: selectedWindowOffset)
                    }
                }
                .padding(.top, 8)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(effectiveColorScheme == .dark ? .jetLighter.opacity(0.2) : .gray.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .navigationDestination(isPresented: $showWorkoutDetail) {
            if let workout = selectedWorkout {
                WorkoutDetailView(workout: workout)
            }
        }
        .navigationDestination(isPresented: $showDailyWorkoutDetail) {
            if let dailyWorkouts = selectedDailyWorkouts {
                DailyWorkoutDetailView(date: dailyWorkouts.date, workouts: dailyWorkouts.workouts)
            }
        }
    }
    
    private func sevenDayView(for windowOffset: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(sortedWindowDays(for: windowOffset), id: \.0) { date, hasWorkout in
                VStack(spacing: 8) {
                    // Day abbreviation
                    Text(dayAbbreviation(for: date))
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                    
                    // Day circle with number - tappable
                    ZStack {
                        Circle()
                            .fill(hasWorkout ? .accent : (effectiveColorScheme == .dark ? .jetLighter.opacity(0.3) : .gray.opacity(0.1)))
                            .frame(width: 44, height: 44)
                        
                        // Day number
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.montserratBold(size: 16))
                            .foregroundStyle(hasWorkout ? .white : (effectiveColorScheme == .dark ? .white.opacity(0.8) : .black))
                        
                        // Fire icon for completed days
                        if hasWorkout {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange)
                                .offset(x: 12, y: -12)
                        }
                    }
                    .onTapGesture {
                        handleDayTap(for: date)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func handleDayTap(for date: Date) {
        let dayWorkouts = getWorkoutsForDate(date)
        
        guard !dayWorkouts.isEmpty else {
            // No workouts - do nothing (maybe add haptic feedback later)
            return
        }
        
        if dayWorkouts.count == 1 {
            // Single workout - navigate directly to WorkoutDetailView
            selectedWorkout = dayWorkouts[0]
            showWorkoutDetail = true
        } else {
            // Multiple workouts - navigate to DailyWorkoutDetailView
            selectedDailyWorkouts = DailyWorkoutNavigation(date: date, workouts: dayWorkouts)
            showDailyWorkoutDetail = true
        }
    }
    
    private func getWorkoutsForDate(_ date: Date) -> [Workout] {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        return workouts.filter { workout in
            calendar.startOfDay(for: workout.date) == targetDate
        }
    }
    
    private func sortedWindowDays(for windowOffset: Int) -> [(Date, Bool)] {
        let calendar = Calendar.current
        let window = sevenDayWindow(for: windowOffset)
        let startOfWindow = calendar.startOfDay(for: window.start)
        let workoutDates = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        
        var result: [(Date, Bool)] = []
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: startOfWindow) {
                let normalizedDay = calendar.startOfDay(for: day)
                let hasWorkout = workoutDates.contains(normalizedDay)
                result.append((day, hasWorkout))
            }
        }
        return result
    }
    
    private func sevenDayWindow(for offset: Int) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endOfWindow = calendar.date(byAdding: .day, value: offset * 7, to: today) ?? today
        let startOfWindow = calendar.date(byAdding: .day, value: -6, to: endOfWindow) ?? endOfWindow
        return (start: startOfWindow, end: endOfWindow)
    }
    
    private func dayAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - Preview
#Preview {
    let sampleWorkouts = [
        Workout(
            name: "Morning Stair Climb",
            date: Date(),
            duration: 1800,
            steps: 2500,
            effortRating: 4.0
        ),
        Workout(
            name: "Evening Session",
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            duration: 2400,
            steps: 3000,
            effortRating: 3.0
        ),
        Workout(
            name: "Quick Workout",
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            duration: 1200,
            steps: 1500,
            effortRating: 2.0
        )
    ]
    
    StreakView(workouts: sampleWorkouts)
        .padding(20)
        .environmentObject(TabRouter())
}

#Preview("Dark") {
    let sampleWorkouts = [
        Workout(
            name: "Morning Stair Climb",
            date: Date(),
            duration: 1800,
            steps: 2500,
            effortRating: 4.0
        ),
        Workout(
            name: "Evening Session",
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            duration: 2400,
            steps: 3000,
            effortRating: 3.0
        )
    ]
    
    StreakView(workouts: sampleWorkouts)
        .padding(20)
        .environmentObject(TabRouter())
        .preferredColorScheme(.dark)
}
