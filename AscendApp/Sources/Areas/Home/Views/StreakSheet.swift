//
//  StreakSheet.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/28/25.
//

import SwiftUI

struct StreakSheet: View {
    let currentStreak: Int
    let workouts: [Workout]
    @Binding var showingProgressSheet: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared
    
    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    // Title
                    HStack {
                        Text("Streak")
                            .font(.montserratBold(size: 28))
                            .foregroundStyle(effectiveColorScheme == .dark ? .white : .black)
                        Spacer()
                    }
                    .padding(.top, 20)

                    // Hero Section - Current Streak
                    StreakHeroView(
                        currentStreak: currentStreak,
                        showMyProgressButton: true,
                        onMyProgressTap: {
                            showingProgressSheet = true
                        }
                    )
                    
                }
                .padding(.horizontal, 24)
            }
            .themedBackground()
        }
        .sheet(isPresented: $showingProgressSheet) {
            ProgressSheet(workouts: workouts)
                .presentationDragIndicator(.visible)
        }
    }
    
}

#Preview {
    @Previewable @State var showProgress = false
    
    let sampleWorkouts = [
        Workout(name: "Test", date: Date(), duration: 1800, steps: 2500)
    ]
    
    StreakSheet(
        currentStreak: 7,
        workouts: sampleWorkouts,
        showingProgressSheet: $showProgress
    )
}

#Preview("Dark Mode") {
    @Previewable @State var showProgress = false
    
    let sampleWorkouts = [
        Workout(name: "Test", date: Date(), duration: 1800, steps: 2500)
    ]
    
    StreakSheet(
        currentStreak: 101,
        workouts: sampleWorkouts,
        showingProgressSheet: $showProgress
    )
    .preferredColorScheme(.dark)
}
