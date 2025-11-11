//
//  LeaderboardViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
class LeaderboardViewModel {
    var selectedMetric: LeaderboardMetric = .steps
    var selectedTimeFrame: LeaderboardTimeFrame = .weekly
    var leaderboardEntries: [LeaderboardEntry] = []
    var userEntry: LeaderboardEntry?
    var isLoading = false
    var errorMessage: String?
    var showingTopLeaders = true
    
    private let service = LeaderboardService.shared
    private let repository = LeaderboardRepository.shared
    private var currentUserId: String?
    
    func configure(userId: String, modelContext: ModelContext) {
        self.currentUserId = userId
        service.configure(modelContext: modelContext)
    }
    
    func refreshLeaderboard(
        userId: String,
        displayName: String,
        photoURL: URL?,
        workouts: [Workout]
    ) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 1. Update local stats from workouts
            try service.updateAllTimeFrames(for: userId, workouts: workouts)
            
            // 2. Sync to Firestore
            try await service.syncToFirestore(
                userId: userId,
                displayName: displayName,
                photoURL: photoURL
            )
            
            // 3. Fetch leaderboard from Firestore
            await loadLeaderboard(userId: userId)
            
        } catch {
            errorMessage = "Failed to refresh leaderboard: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func loadLeaderboard(userId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let stats = try await repository.fetchLeaderboard(
                metric: selectedMetric,
                timeFrame: selectedTimeFrame,
                limit: 100
            )
            
            // Convert to leaderboard entries with rankings
            var entries: [LeaderboardEntry] = []
            for (index, stat) in stats.enumerated() {
                let value = stat.value(for: selectedMetric)
                let entry = LeaderboardEntry(
                    userId: stat.userId,
                    displayName: stat.displayName,
                    photoURL: stat.photoURL.flatMap { URL(string: $0) },
                    rank: index + 1,
                    value: value,
                    formattedValue: formatValue(value, for: selectedMetric),
                    isCurrentUser: stat.userId == userId
                )
                
                entries.append(entry)
                
                if stat.userId == userId {
                    userEntry = entry
                }
            }
            
            leaderboardEntries = entries
            
            // If user not in leaderboard yet, create a placeholder entry
            if userEntry == nil {
                if let localStats = try service.getLocalStats(for: userId, timeFrame: selectedTimeFrame) {
                    let value = localStats.value(for: selectedMetric)
                    userEntry = LeaderboardEntry(
                        userId: userId,
                        displayName: "You",
                        photoURL: nil,
                        rank: entries.count + 1,
                        value: value,
                        formattedValue: formatValue(value, for: selectedMetric),
                        isCurrentUser: true
                    )
                }
            }
            
        } catch {
            errorMessage = "Failed to load leaderboard: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func toggleView() {
        showingTopLeaders.toggle()
    }
    
    func scrollToUser() {
        showingTopLeaders = false
    }
    
    private func formatValue(_ value: Double, for metric: LeaderboardMetric) -> String {
        switch metric {
        case .steps, .workouts:
            return String(format: "%.0f", value)
        case .duration:
            return formatDuration(value)
        case .stepsPerMinute:
            return String(format: "%.1f", value)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
