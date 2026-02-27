//
//  FeatureFlags.swift
//  AscendApp
//
//  Created by Claude Code on 1/11/26.
//

import Foundation

/// Central configuration for feature flags
/// Use this to easily enable/disable features during development or before full rollout
enum FeatureFlags {

    // MARK: - Integrations

    /// Enable/disable the entire Strava integration feature
    /// Set to `false` to hide all Strava-related UI and functionality
    /// Useful when Strava API approval is pending (limited to 1 athlete)
    static let isStravaEnabled = false

    // MARK: - Import

    /// Enable/disable the post-import celebration screen
    /// Kill switch for safe rollout — disabling reverts to old auto-dismiss behavior
    static let isImportCelebrationEnabled = true

    // MARK: - Future Flags
    // Add more feature flags here as needed
    // static let isNewFeatureEnabled = false
}
