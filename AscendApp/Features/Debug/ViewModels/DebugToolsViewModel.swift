//
//  DebugToolsViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import Observation

#if DEBUG
@MainActor
@Observable
class DebugToolsViewModel {
    private let service = DebugToolsService.shared

    var executingActionId: UUID?  // Track which specific action is executing
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Debug Sections Configuration

    var sections: [DebugSection] {
        [
            leaderboardSection
            // Easy to add more sections:
            // workoutsSection,
            // authSection,
        ]
    }

    // MARK: - Leaderboard Section

    private var leaderboardSection: DebugSection {
        DebugSection(
            title: "Leaderboards",
            subtitle: "Manage test leaderboard data",
            actions: [
                DebugAction(
                    title: "Seed Test Data",
                    description: "Seeds leaderboard entries for YOUR account across all time frames. For multi-user data, run: node scripts/seed-leaderboard.mjs seed --project dev",
                    icon: "arrow.down.doc.fill",
                    iconColor: .accent
                ),
                DebugAction(
                    title: "Clear Test Data",
                    description: "Clears YOUR seeded leaderboard entries.",
                    icon: "trash.fill",
                    iconColor: .red,
                    isDestructive: true
                )
            ]
        )
    }

    // MARK: - Action Execution

    func executeAction(_ action: DebugAction) async {
        executingActionId = action.id  // Set the specific action being executed
        errorMessage = nil
        successMessage = nil

        do {
            // Map action titles to service methods
            switch action.title {
            case "Seed Test Data":
                try await service.seedLeaderboardData()
                successMessage = "Successfully seeded test data!"

            case "Clear Test Data":
                try await service.clearLeaderboardData()
                successMessage = "Successfully cleared test data!"

            default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        executingActionId = nil
    }

    // ✅ Helper to check if a specific action is executing
    func isExecuting(_ action: DebugAction) -> Bool {
        return executingActionId == action.id
    }
}
#endif
