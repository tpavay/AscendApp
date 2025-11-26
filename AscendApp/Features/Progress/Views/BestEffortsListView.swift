//
//  BestEffortsListView.swift
//  AscendApp
//
//  Created by GPT-5.1 on 11/20/25.
//

import SwiftUI

struct BestEffortsListView: View {
    let workouts: [Workout]
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    private var efforts: [BestEffort] {
        BestEffortsBuilder.bestEfforts(from: workouts)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if efforts.isEmpty {
                    emptyState
                } else {
                    effortsList
                }
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .themedBackground()
        .navigationTitle("Best Efforts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: BestEffortsProgressView(workouts: workouts)) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.accent)
                }
            }
        }
    }
    
    private var effortsList: some View {
        VStack(spacing: 12) {
            ForEach(efforts) { effort in
                NavigationLink(destination: WorkoutDetailView(workout: effort.workout)) {
                    BestEffortCard(effort: effort, colorScheme: effectiveColorScheme)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No Best Efforts Yet")
                .font(.montserratSemiBold(size: 18))
                .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
            
            Text("Start logging workouts to see your all‑time best sessions for steps, duration, heart rate, and more.")
                .font(.montserratRegular(size: 14))
                .foregroundStyle(effectiveColorScheme == .dark ? .white.opacity(0.7) : .gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(effectiveColorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
}

private struct BestEffortCard: View {
    let effort: BestEffort
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: effort.iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.accent)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(effort.title)
                    .font(.montserratSemiBold(size: 16))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)
                
                Text(effort.detailText)
                    .font(.montserratRegular(size: 13))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .gray)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Text(effort.valueText)
                .font(.montserratBold(size: 16))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(colorScheme == .dark ? .white.opacity(0.08) : .gray.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    let sampleWorkouts = [
        Workout(
            name: "Morning Climb",
            date: Date(),
            duration: 45 * 60,
            steps: 5200,
            floors: 40,
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
            steps: 4300,
            floors: 32,
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
}

