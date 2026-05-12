//
//  BestEffortUIStyle.swift
//  AscendApp
//
//  Created by Codex on 5/10/26.
//

import SwiftUI

enum BestEffortUIStyle {
    static func trophyColor(for rank: Int) -> Color {
        switch rank {
        case 1:
            return Color(red: 1.0, green: 0.76, blue: 0.18)
        case 2:
            return Color(red: 0.78, green: 0.8, blue: 0.86)
        case 3:
            return Color(red: 0.76, green: 0.46, blue: 0.24)
        default:
            return .accent
        }
    }
}

extension RankedBestEffort {
    var trophyColor: Color {
        BestEffortUIStyle.trophyColor(for: rank)
    }
}
