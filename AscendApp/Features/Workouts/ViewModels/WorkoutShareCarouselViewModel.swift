//
//  WorkoutShareCarouselViewModel.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import Foundation
import SwiftUI
import UIKit

/// Types of cards available in the carousel.
/// v1 ships a single bundled poster card while keeping the carousel shell in place.
enum ShareCardType: Identifiable, Equatable {
    case poster
    case liveClimb(Climb)

    var id: String {
        switch self {
        case .poster:
            return "poster"
        case .liveClimb(let climb):
            return "liveClimb-\(climb.id)"
        }
    }

    var preset: WorkoutShareCardPreset {
        switch self {
        case .poster, .liveClimb:
            return .defaultSquarePoster
        }
    }
}

@MainActor
@Observable
final class WorkoutShareCarouselViewModel {
    static let posterExportSize = CGSize(width: 1080, height: 1080)
    static let displayCardSize: CGFloat = 344
    static let displayCardWidth: CGFloat = displayCardSize
    static let displayCardHeight: CGFloat = displayCardSize

    var currentCardIndex: Int = 0
    var copyConfirmationText: String?
    var shareErrorMessage: String?

    let workout: Workout
    let workoutCount: Int?
    var liveClimbRank: Int?
    var liveClimbRankTotal: Int?
    var liveClimbRankIsLoading = false
    let availableCards: [ShareCardType]

    private let composer = WorkoutShareCardComposer()
    private let leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared

    var currentCardType: ShareCardType {
        guard currentCardIndex < availableCards.count else {
            return .poster
        }
        return availableCards[currentCardIndex]
    }

    init(workout: Workout, workoutCount: Int) {
        self.workout = workout
        self.workoutCount = workoutCount
        self.liveClimbRank = nil
        self.liveClimbRankTotal = nil
        self.availableCards = Self.availableCards(for: workout)
    }

    init(workout: Workout, liveClimbRank: Int? = nil, liveClimbRankTotal: Int? = nil) {
        self.workout = workout
        self.workoutCount = nil
        self.liveClimbRank = liveClimbRank
        self.liveClimbRankTotal = liveClimbRankTotal
        self.availableCards = Self.availableCards(for: workout)
    }

    func composition(
        for cardType: ShareCardType,
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        bestEffort: RankedBestEffort? = nil
    ) -> WorkoutShareCardComposition {
        composer.compose(
            workout: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            preset: cardType.preset,
            bestEffort: bestEffort
        )
    }

    func renderCurrentCard(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        bestEffort: RankedBestEffort? = nil
    ) -> UIImage? {
        let content = currentCardView(
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            bestEffort: bestEffort
        )
        .frame(width: Self.displayCardWidth, height: Self.displayCardHeight)

        let renderer = ImageRenderer(content: content)
        renderer.scale = Self.posterExportSize.width / Self.displayCardWidth
        renderer.isOpaque = false
        return renderer.uiImage
    }

    @ViewBuilder
    func currentCardView(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        bestEffort: RankedBestEffort? = nil
    ) -> some View {
        cardView(
            for: currentCardType,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            bestEffort: bestEffort
        )
    }

    @ViewBuilder
    func cardView(
        for cardType: ShareCardType,
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        bestEffort: RankedBestEffort? = nil
    ) -> some View {
        switch cardType {
        case .poster:
            WorkoutSquareShareCard(
                composition: composition(
                    for: cardType,
                    measurementSystem: measurementSystem,
                    stepHeight: stepHeight,
                    bestEffort: bestEffort
                )
            )
        case .liveClimb(let climb):
            WorkoutLiveClimbShareCard(
                workout: workout,
                climb: climb,
                rank: liveClimbRank,
                rankTotal: liveClimbRankTotal,
                isRankLoading: liveClimbRankIsLoading,
                bestEffortText: bestEffort?.sentence
            )
        }
    }

    func loadLiveClimbCompletionRankIfNeeded() async {
        guard liveClimbRank == nil,
              !liveClimbRankIsLoading,
              let climb = availableCards.compactMap({ cardType -> Climb? in
                  if case .liveClimb(let climb) = cardType {
                      return climb
                  }
                  return nil
              }).first
        else {
            return
        }

        liveClimbRankIsLoading = true
        defer {
            liveClimbRankIsLoading = false
        }

        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )

        do {
            let completionRank = try await leaderboardService.fetchCompletionRank(
                context: context,
                completionDurationSeconds: workout.duration
            )

            withAnimation(.easeOut(duration: 0.2)) {
                liveClimbRank = completionRank.rank
                liveClimbRankTotal = completionRank.completedCount
            }
        } catch {
#if DEBUG
            print("Live Climb completion rank fetch failed: \(error.localizedDescription)")
#endif
        }
    }

    func shareText(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        bestEffort: RankedBestEffort? = nil
    ) -> String {
        workoutShareText(
            for: workout,
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            bestEffort: bestEffort
        )
    }

    func copyShareText(
        measurementSystem: MeasurementSystem,
        stepHeight: Double,
        bestEffort: RankedBestEffort? = nil
    ) {
        UIPasteboard.general.string = shareText(
            measurementSystem: measurementSystem,
            stepHeight: stepHeight,
            bestEffort: bestEffort
        )
        showCopyConfirmation("Copied!")
    }

    func showCopyConfirmation(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            copyConfirmationText = text
        }

        Task {
            try await Task.sleep(for: .milliseconds(1600))
            withAnimation(.easeOut(duration: 0.3)) {
                copyConfirmationText = nil
            }
        }
    }

    private static func availableCards(for workout: Workout) -> [ShareCardType] {
        guard let climb = LiveClimbWorkoutSummaryData.climb(for: workout) else {
            return [.poster]
        }

        return [.liveClimb(climb), .poster]
    }
}
