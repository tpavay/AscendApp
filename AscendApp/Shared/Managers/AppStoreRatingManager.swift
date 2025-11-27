//
//  AppStoreRatingManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/27/25.
//

import StoreKit
import SwiftUI

/// Manages App Store rating prompts with intelligent timing
/// Prompts at 20 workouts, then every 30 workouts thereafter
@MainActor
final class AppStoreRatingManager {
    static let shared = AppStoreRatingManager()

    private init() {}

    // MARK: - Constants

    private enum Constants {
        static let firstPromptThreshold = 20
        static let subsequentPromptInterval = 30
        static let userDefaultsKey = "lastRatingPromptWorkoutCount"
    }

    // MARK: - UserDefaults

    private var lastPromptedWorkoutCount: Int {
        get { UserDefaults.standard.integer(forKey: Constants.userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.userDefaultsKey) }
    }

    // MARK: - Public Methods

    /// Check if the user is eligible for a rating prompt based on current workout count
    /// - Parameter currentWorkoutCount: Total number of workouts the user has logged
    /// - Returns: True if the user should be prompted for a rating
    func shouldPromptForRating(currentWorkoutCount: Int) -> Bool {
        // Haven't reached minimum threshold yet
        guard currentWorkoutCount >= Constants.firstPromptThreshold else {
            return false
        }

        // First time reaching 20 workouts
        if lastPromptedWorkoutCount == 0 && currentWorkoutCount >= Constants.firstPromptThreshold {
            return true
        }

        // Check if we've reached another interval (50, 80, 110, etc.)
        let workoutsSinceLastPrompt = currentWorkoutCount - lastPromptedWorkoutCount
        return workoutsSinceLastPrompt >= Constants.subsequentPromptInterval
    }

    /// Request an App Store rating prompt
    /// Apple will decide whether to actually show it based on system limitations
    /// - Parameter currentWorkoutCount: Current workout count to track when we prompted
    func requestReview(currentWorkoutCount: Int) {
        // Update the last prompted count
        lastPromptedWorkoutCount = currentWorkoutCount

        // Request the review from Apple
        // Note: Apple controls whether the prompt is actually shown based on:
        // - User's "In-App Ratings & Reviews" setting
        // - System-wide rate limiting (3 prompts per 365 days)
        // - Recent rating activity across all apps
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    /// Check eligibility and request review if appropriate
    /// - Parameter currentWorkoutCount: Total number of workouts the user has logged
    /// - Returns: True if a review was requested, false otherwise
    @discardableResult
    func checkAndRequestReviewIfNeeded(currentWorkoutCount: Int) -> Bool {
        guard shouldPromptForRating(currentWorkoutCount: currentWorkoutCount) else {
            return false
        }

        requestReview(currentWorkoutCount: currentWorkoutCount)
        return true
    }

    // MARK: - Testing Support

    /// Reset the rating prompt state (for testing purposes)
    func resetPromptState() {
        lastPromptedWorkoutCount = 0
    }
}
