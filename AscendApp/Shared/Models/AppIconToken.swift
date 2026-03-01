//
//  AppIconToken.swift
//  AscendApp
//
//  Created by Codex on 2/28/26.
//

import Foundation

enum AppIconToken: Hashable, Sendable {
    case tabHome
    case tabHomeSelected
    case tabWorkouts
    case tabWorkoutsSelected
    case tabProgress
    case tabProgressSelected
    case tabLeaderboard
    case tabLeaderboardSelected
    case tabSettings
    case tabSettingsSelected

    case settingsEditProfile
    case settingsAppearance
    case settingsWorkoutMetric
    case settingsMeasurementSystem
    case settingsWeekStart
    case settingsIntegrations
    case settingsDebugTools
    case settingsPrivacyPolicy
    case settingsContactUs
    case settingsDeleteAccount
    case settingsNotifications

    case disclosureChevronRight

    enum Source: Hashable, Sendable {
        case asset(String)
        case systemSymbol(String)
    }

    var source: Source {
        switch self {
        case .tabHome:
            return .asset("ph-tab-home")
        case .tabHomeSelected:
            return .asset("ph-tab-home-selected")
        case .tabWorkouts:
            return .asset("ph-tab-workouts")
        case .tabWorkoutsSelected:
            return .asset("ph-tab-workouts-selected")
        case .tabProgress:
            return .asset("ph-tab-progress")
        case .tabProgressSelected:
            return .asset("ph-tab-progress-selected")
        case .tabLeaderboard:
            return .asset("ph-tab-leaderboard")
        case .tabLeaderboardSelected:
            return .asset("ph-tab-leaderboard-selected")
        case .tabSettings:
            return .asset("ph-tab-settings")
        case .tabSettingsSelected:
            return .asset("ph-tab-settings-selected")

        case .settingsEditProfile:
            return .asset("ph-settings-edit-profile")
        case .settingsAppearance:
            return .asset("ph-settings-appearance")
        case .settingsWorkoutMetric:
            return .asset("ph-settings-workout-metric")
        case .settingsMeasurementSystem:
            return .asset("ph-settings-measurement-system")
        case .settingsWeekStart:
            return .systemSymbol("calendar")
        case .settingsIntegrations:
            return .asset("ph-settings-integrations")
        case .settingsDebugTools:
            return .asset("ph-settings-debug-tools")
        case .settingsPrivacyPolicy:
            return .asset("ph-settings-privacy-policy")
        case .settingsContactUs:
            return .asset("ph-settings-contact-us")
        case .settingsDeleteAccount:
            return .asset("ph-settings-delete-account")
        case .settingsNotifications:
            return .asset("ph-settings-notifications")

        case .disclosureChevronRight:
            return .asset("ph-disclosure-chevron-right")
        }
    }
}
