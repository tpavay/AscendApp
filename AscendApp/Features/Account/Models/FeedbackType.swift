//
//  FeedbackType.swift
//  AscendApp
//
//  Created by Claude on 1/4/26.
//

import SwiftUI

enum FeedbackType: String, CaseIterable, Identifiable {
    case featureRequest = "feature_request"
    case bugReport = "bug_report"
    case getHelp = "get_help"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .featureRequest: return "Feature Request"
        case .bugReport: return "Bug Report"
        case .getHelp: return "Get Help"
        }
    }

    var description: String {
        switch self {
        case .featureRequest: return "Suggest a new feature"
        case .bugReport: return "Report an issue"
        case .getHelp: return "Ask a question"
        }
    }

    var icon: String {
        switch self {
        case .featureRequest: return "lightbulb"
        case .bugReport: return "ladybug"
        case .getHelp: return "questionmark.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .featureRequest: return .yellow
        case .bugReport: return .red
        case .getHelp: return .blue
        }
    }

    var placeholderText: String {
        switch self {
        case .featureRequest:
            return "Describe the feature you'd like to see in Ascend..."
        case .bugReport:
            return "Describe the bug you encountered. Include steps to reproduce if possible..."
        case .getHelp:
            return "What do you need help with? We'll get back to you as soon as possible..."
        }
    }

    var navigationTitle: String {
        switch self {
        case .featureRequest: return "Feature Request"
        case .bugReport: return "Report a Bug"
        case .getHelp: return "Get Help"
        }
    }
}
