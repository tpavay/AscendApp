//
//  AppStoreRatingManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/27/25.
//

import StoreKit
import SwiftUI

/// Manages App Store rating prompts with intelligent timing
/// Shows custom prompt first, then system prompt if user agrees
/// Prompts at 10 workouts, then every 30 workouts thereafter
@MainActor
@Observable
final class AppStoreRatingManager {
    static let shared = AppStoreRatingManager()

    private init() {}

    // MARK: - Observable State
    
    /// Whether to show the custom rating prompt overlay
    var showCustomPrompt = false

    // MARK: - Constants

    private enum Constants {
        static let firstPromptThreshold = 10  // Lowered from 20 for earlier engagement
        static let subsequentPromptInterval = 30
        static let userDefaultsKey = "lastRatingPromptWorkoutCount"
        static let notNowDelayDays = 14  // Days to wait after user taps "Not Now"
        static let lastNotNowDateKey = "lastRatingNotNowDate"
    }

    // MARK: - UserDefaults

    private var lastPromptedWorkoutCount: Int {
        get { UserDefaults.standard.integer(forKey: Constants.userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.userDefaultsKey) }
    }
    
    private var lastNotNowDate: Date? {
        get { UserDefaults.standard.object(forKey: Constants.lastNotNowDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Constants.lastNotNowDateKey) }
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
        
        // Check if user recently tapped "Not Now"
        if let lastNotNow = lastNotNowDate {
            let daysSinceNotNow = Calendar.current.dateComponents([.day], from: lastNotNow, to: Date()).day ?? 0
            if daysSinceNotNow < Constants.notNowDelayDays {
                return false
            }
        }

        // First time reaching threshold
        if lastPromptedWorkoutCount == 0 && currentWorkoutCount >= Constants.firstPromptThreshold {
            return true
        }

        // Check if we've reached another interval
        let workoutsSinceLastPrompt = currentWorkoutCount - lastPromptedWorkoutCount
        return workoutsSinceLastPrompt >= Constants.subsequentPromptInterval
    }
    
    /// Show the custom rating prompt overlay
    /// - Parameter currentWorkoutCount: Current workout count to track when we prompted
    func showCustomRatingPrompt(currentWorkoutCount: Int) {
        lastPromptedWorkoutCount = currentWorkoutCount
        showCustomPrompt = true
    }
    
    /// Called when user taps "Rate Us" on custom prompt
    func userTappedRateUs() {
        showCustomPrompt = false
        requestSystemReview()
    }
    
    /// Called when user taps "Not Now" on custom prompt
    func userTappedNotNow() {
        showCustomPrompt = false
        lastNotNowDate = Date()
    }

    /// Request the system App Store rating prompt
    /// Apple will decide whether to actually show it based on system limitations
    func requestSystemReview() {
        // Request the review from Apple
        // Note: Apple controls whether the prompt is actually shown based on:
        // - User's "In-App Ratings & Reviews" setting
        // - System-wide rate limiting (3 prompts per 365 days)
        // - Recent rating activity across all apps
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }

        if #available(iOS 18.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
    
    /// Legacy method - Request an App Store rating prompt directly
    /// - Parameter currentWorkoutCount: Current workout count to track when we prompted
    func requestReview(currentWorkoutCount: Int) {
        lastPromptedWorkoutCount = currentWorkoutCount
        requestSystemReview()
    }

    /// Check eligibility and show custom prompt if appropriate
    /// - Parameter currentWorkoutCount: Total number of workouts the user has logged
    /// - Returns: True if a prompt was shown, false otherwise
    @discardableResult
    func checkAndShowPromptIfNeeded(currentWorkoutCount: Int) -> Bool {
        guard shouldPromptForRating(currentWorkoutCount: currentWorkoutCount) else {
            return false
        }

        showCustomRatingPrompt(currentWorkoutCount: currentWorkoutCount)
        return true
    }
    
    /// Legacy method - Check eligibility and request review if appropriate
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
