//
//  HomeView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/10/25.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AuthenticationViewModel.self) private var authVM
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]

    var body: some View {
        VStack(spacing: 24) {
            // Header Section
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome")
                    .font(.montserratRegular(size: 18))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.8) : .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(authVM.displayName.isEmpty ? "User" : authVM.displayName)
                    .font(.montserratBold(size: 28))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Main Content Area
            VStack(spacing: 20) {
                // Streak & Activity Section
                StreakView(workouts: workouts)
            }
            
            Spacer()
        }
        .padding(20)
        .themedBackground()
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AuthenticationViewModel())
    }
    .modelContainer(for: Workout.self, inMemory: true)
}
