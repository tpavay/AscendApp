//
//  HapticsManager.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import UIKit

/// Centralized manager for haptic feedback throughout the app
/// Provides consistent haptic patterns for different interaction types
@MainActor
final class HapticsManager {
    static let shared = HapticsManager()
    
    private init() {}
    
    // MARK: - Haptic Types
    
    enum HapticType: Sendable {
        /// Light tap for selections, toggles, and minor interactions
        case selection
        /// Light impact for button taps and subtle feedback
        case lightImpact
        /// Medium impact for more significant interactions
        case mediumImpact
        /// Heavy impact for major interactions or reaching limits
        case heavyImpact
        /// Success notification for completed actions
        case success
        /// Warning notification for destructive or important actions
        case warning
        /// Error notification for failed actions
        case error
    }
    
    // MARK: - Public Methods
    
    /// Trigger a haptic feedback of the specified type
    func trigger(_ type: HapticType) {
        switch type {
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        case .lightImpact:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .mediumImpact:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .heavyImpact:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}

