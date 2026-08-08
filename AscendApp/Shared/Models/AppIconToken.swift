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
    case tabLeaderboard
    case tabLeaderboardSelected
    case tabProfile
    case tabProfileSelected
    case mapPin
    case mapPinFill
    case globeHemisphereWest
    case mountains
    case infinity
    case clipboardText
    case manualWorkout

    case settingsEditProfile
    case settingsMeasurementSystem
    case settingsWeekStart
    case settingsIntegrations
    case settingsDebugTools
    case settingsTermsOfService
    case settingsPrivacyPolicy
    case settingsContactUs
    case settingsDeleteAccount
    case settingsNotifications
    case settingsRestorePurchases
    case settingsManageSubscription
    case settingsBlockedClimbers
    case profileBirthday
    case profileGender
    case profileWeight

    case disclosureChevronRight
    case bestEffortTrophy
    case bestEffortChartLine
    case bestEffortClock

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
        case .tabLeaderboard:
            return .asset("ph-tab-leaderboard")
        case .tabLeaderboardSelected:
            return .asset("ph-tab-leaderboard-selected")
        case .tabProfile:
            return .systemSymbol("person.crop.circle")
        case .tabProfileSelected:
            return .systemSymbol("person.crop.circle.fill")
        case .mapPin:
            return .asset("ph-map-pin")
        case .mapPinFill:
            return .asset("ph-map-pin-fill")
        case .globeHemisphereWest:
            return .asset("ph-globe-hemisphere-west")
        case .mountains:
            return .asset("ph-mountains")
        case .infinity:
            return .asset("ph-infinity")
        case .clipboardText:
            return .asset("ph-clipboard-text")
        case .manualWorkout:
            return .systemSymbol("square.and.pencil")

        case .settingsEditProfile:
            return .asset("ph-settings-edit-profile")
        case .settingsMeasurementSystem:
            return .asset("ph-settings-measurement-system")
        case .settingsWeekStart:
            return .systemSymbol("calendar")
        case .settingsIntegrations:
            return .asset("ph-settings-integrations")
        case .settingsDebugTools:
            return .asset("ph-settings-debug-tools")
        case .settingsTermsOfService:
            return .systemSymbol("doc.text")
        case .settingsPrivacyPolicy:
            return .asset("ph-settings-privacy-policy")
        case .settingsContactUs:
            return .asset("ph-settings-contact-us")
        case .settingsDeleteAccount:
            return .asset("ph-settings-delete-account")
        case .settingsNotifications:
            return .asset("ph-settings-notifications")
        case .settingsRestorePurchases:
            return .systemSymbol("arrow.clockwise")
        case .settingsManageSubscription:
            return .systemSymbol("creditcard")
        case .settingsBlockedClimbers:
            return .systemSymbol("person.crop.circle.badge.xmark")
        case .profileBirthday:
            return .systemSymbol("calendar")
        case .profileGender:
            return .systemSymbol("person.crop.circle")
        case .profileWeight:
            return .systemSymbol("scalemass")

        case .disclosureChevronRight:
            return .asset("ph-disclosure-chevron-right")
        case .bestEffortTrophy:
            return .asset("ph-best-effort-trophy")
        case .bestEffortChartLine:
            return .asset("ph-best-effort-chart-line")
        case .bestEffortClock:
            return .asset("ph-best-effort-clock")
        }
    }
}
