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

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationGenerator = UINotificationFeedbackGenerator()

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
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .lightImpact:
            lightImpactGenerator.impactOccurred()
            lightImpactGenerator.prepare()
        case .mediumImpact:
            mediumImpactGenerator.impactOccurred()
            mediumImpactGenerator.prepare()
        case .heavyImpact:
            heavyImpactGenerator.impactOccurred()
            heavyImpactGenerator.prepare()
        case .success:
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        case .error:
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
        }
    }

    /// Pulse used while a perimeter/trace animation is moving.
    /// Intensity ramps with progress for a smoother directional feel.
    func triggerTraceSweep(progress: Double) {
        let clamped = min(max(progress, 0), 1)
        let intensity = CGFloat(0.28 + (clamped * 0.62))
        rigidImpactGenerator.impactOccurred(intensity: intensity)
        rigidImpactGenerator.prepare()
    }

    /// Strong landing burst for the final stat impact.
    func finalStatImpactBurst() async {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        heavy.prepare()
        rigid.prepare()

        heavy.impactOccurred(intensity: 1.0)
        try? await Task.sleep(for: .milliseconds(45))
        rigid.impactOccurred(intensity: 1.0)
        try? await Task.sleep(for: .milliseconds(55))
        heavy.impactOccurred(intensity: 1.0)
    }

    // MARK: - Celebration Bursts

    /// Light×3 rapid taps followed by a success notification
    func celebrationBurst() async {
        let light = UIImpactFeedbackGenerator(style: .light)
        light.prepare()

        for _ in 0..<3 {
            light.impactOccurred()
            try? await Task.sleep(for: .milliseconds(60))
        }

        try? await Task.sleep(for: .milliseconds(80))
        let notification = UINotificationFeedbackGenerator()
        notification.prepare()
        notification.notificationOccurred(.success)
    }

    /// Heavy×3 rapid taps followed by a success notification — used for goal completion
    func goalCompletionBurst() async {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.prepare()

        for _ in 0..<3 {
            heavy.impactOccurred()
            try? await Task.sleep(for: .milliseconds(80))
        }

        try? await Task.sleep(for: .milliseconds(100))
        let notification = UINotificationFeedbackGenerator()
        notification.prepare()
        notification.notificationOccurred(.success)
    }
}
