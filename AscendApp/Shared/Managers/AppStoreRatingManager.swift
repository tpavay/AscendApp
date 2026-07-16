//
//  AppStoreRatingManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/27/25.
//

import StoreKit
import SwiftUI

/// Manages App Store rating prompts behind an app-owned sentiment question.
@MainActor
final class AppStoreRatingManager {
    static let shared = AppStoreRatingManager()

    private init() {}

    enum EnjoymentResponse: String, Equatable {
        case yes
        case no
    }

    // MARK: - Constants

    private enum Constants {
        static let firstEligibleLiveClimbCompletionCount = 1
        static let enjoymentResponseKey = "appStoreRatingEnjoymentResponse"
        static let lastReviewRequestAtKey = "lastAppStoreRatingRequestAt"
    }

    // MARK: - UserDefaults

    private var storedEnjoymentResponse: EnjoymentResponse? {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Constants.enjoymentResponseKey) else {
                return nil
            }

            return EnjoymentResponse(rawValue: rawValue)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: Constants.enjoymentResponseKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.enjoymentResponseKey)
            }
        }
    }

    private var lastReviewRequestAt: Date? {
        get { UserDefaults.standard.object(forKey: Constants.lastReviewRequestAtKey) as? Date }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Constants.lastReviewRequestAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.lastReviewRequestAtKey)
            }
        }
    }

    // MARK: - Public Methods

    func shouldAskEnjoymentQuestionAfterFirstLiveClimb(completedLiveClimbCount: Int) -> Bool {
        completedLiveClimbCount == Constants.firstEligibleLiveClimbCompletionCount
            && storedEnjoymentResponse == nil
    }

    func recordEnjoymentResponse(_ response: EnjoymentResponse) {
        storedEnjoymentResponse = response
        LifecycleEventRecorder.shared.recordRatingPromptAnswered(
            response: response.rawValue
        )
    }

    /// Request the native App Store review prompt.
    ///
    /// Apple does not expose whether the prompt was shown or whether the user rated.
    /// We only track that Ascend asked Apple to show it.
    func requestReview() {
        lastReviewRequestAt = Date()
        LifecycleEventRecorder.shared.recordAppStoreReviewRequested(
            reason: "rating_prompt_yes"
        )

        // Apple controls whether the prompt is actually shown based on:
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

    // MARK: - Testing Support

    /// Reset the rating prompt state (for testing purposes)
    func resetPromptState() {
        storedEnjoymentResponse = nil
        lastReviewRequestAt = nil
    }
}
