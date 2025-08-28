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
    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared
    @State private var selectedDate = Date()
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var currentStreak: Int {
        Workout.calculateCurrentStreak(from: workouts)
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
    
    var body: some View {
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
            
            // Hero section with current streak
            StreakHeroView(currentStreak: currentStreak)
                .padding(32)

            // Calendar section
            calendarSection

            Spacer()
        }
        .themedBackground()
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
                        .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                }
            }
            .padding(.horizontal, 24)
            
            // Calendar grid
            calendarGrid
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(effectiveColorScheme == .dark ? .white.opacity(0.1) : .gray.opacity(0.2), lineWidth: 1)
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
    
    private func calendarDay(_ dayData: CalendarDay) -> some View {
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
                .foregroundStyle(
                    dayData.isCurrentMonth ? 
                        (dayData.hasWorkout ? .white : (effectiveColorScheme == .dark ? .white : .black)) :
                        (effectiveColorScheme == .dark ? .white.opacity(0.3) : .gray.opacity(0.5))
                )
        }
        .opacity(dayData.isCurrentMonth ? 1.0 : 0.6)
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
            selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
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
