//
//  FeedbackService.swift
//  AscendApp
//
//  Created by Claude on 1/4/26.
//

import Foundation
import FirebaseFirestore
import UIKit

/// Service responsible for submitting user feedback to Firestore with rate limiting
@MainActor
final class FeedbackService {

    static let shared = FeedbackService()

    enum FeedbackError: LocalizedError {
        case notAuthenticated
        case rateLimited(secondsRemaining: Int)
        case submissionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to submit feedback."
            case .rateLimited(let seconds):
                return "Please wait \(seconds) seconds before submitting again."
            case .submissionFailed(let message):
                return "Failed to submit feedback: \(message)"
            }
        }
    }

    private let db = Firestore.firestore()
    private let cooldownSeconds: TimeInterval = 60
    private let lastSubmissionKey = "lastFeedbackSubmissionTimestamp"

    private init() {}

    /// Check if user is within cooldown period
    /// - Returns: Remaining seconds if in cooldown, nil if can submit
    func getCooldownRemaining() -> Int? {
        guard let lastSubmission = UserDefaults.standard.object(forKey: lastSubmissionKey) as? Date else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(lastSubmission)
        let remaining = cooldownSeconds - elapsed

        if remaining > 0 {
            return Int(ceil(remaining))
        }

        return nil
    }

    /// Submit feedback to Firestore
    /// - Parameters:
    ///   - type: The type of feedback (feature request, bug report, or get help)
    ///   - message: The user's feedback message
    ///   - userId: The authenticated user's ID
    ///   - userEmail: The user's email (optional)
    func submitFeedback(
        type: FeedbackType,
        message: String,
        userId: String,
        userEmail: String?
    ) async throws {
        // Check rate limit
        if let remainingSeconds = getCooldownRemaining() {
            throw FeedbackError.rateLimited(secondsRemaining: remainingSeconds)
        }

        // Gather device info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let deviceModel = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion

        // Create feedback document
        let feedback: [String: Any] = [
            "type": type.rawValue,
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "userId": userId,
            "userEmail": userEmail ?? "",
            "timestamp": FieldValue.serverTimestamp(),
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "deviceModel": deviceModel,
            "osVersion": osVersion,
            "status": "new"
        ]

        do {
            // Submit feedback
            try await db.collection("feedback").addDocument(data: feedback)

            // Update rate limit tracking (both local and Firestore)
            UserDefaults.standard.set(Date(), forKey: lastSubmissionKey)

            // Update server-side rate limit doc
            try await db.collection("userRateLimits").document(userId).setData([
                "lastFeedback": FieldValue.serverTimestamp()
            ], merge: true)

        } catch {
            throw FeedbackError.submissionFailed(error.localizedDescription)
        }
    }
}
