//
//  ProgressTabView.swift
//  AscendApp
//
//  Created by ChatGPT on 3/15/24.
//

import SwiftUI
import SwiftData

struct ProgressTabView: View {
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    
    var body: some View {
        ProgressSheet(workouts: workouts)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        ProgressTabView()
    }
    .modelContainer(for: Workout.self, inMemory: true)
}
