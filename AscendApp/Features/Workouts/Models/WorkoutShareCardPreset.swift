//
//  WorkoutShareCardPreset.swift
//  AscendApp
//
//  Created by Codex on 3/28/26.
//

import CoreGraphics

enum WorkoutShareCardFontToken: String, Equatable {
    case overline
    case label
    case value
    case display
}

enum WorkoutShareCardBackgroundStyle: Equatable {
    case asset(String)
    case transparent
}

struct WorkoutShareCardTextStyle: Equatable {
    let token: WorkoutShareCardFontToken
    let size: CGFloat
    let tracking: CGFloat
}

struct WorkoutShareCardPreset: Equatable {
    struct Surface: Equatable {
        let background: WorkoutShareCardBackgroundStyle
        let cornerRadius: CGFloat
        let borderWidth: CGFloat
        let borderOpacity: Double
    }

    struct Header: Equatable {
        let leadingText: String
        let trailingText: String
        let topPadding: CGFloat
        let height: CGFloat
        let leadingXRatio: CGFloat
        let trailingXRatio: CGFloat
        let textY: CGFloat
    }

    struct Layout: Equatable {
        let heroTopPadding: CGFloat
        let heroWidthRatio: CGFloat
        let heroLabelTopPadding: CGFloat
        let supportingStatsTopPadding: CGFloat
        let supportingStatsWidthRatio: CGFloat
        let supportingStatsSpacing: CGFloat
    }

    struct Typography: Equatable {
        let brand: WorkoutShareCardTextStyle
        let heroLabel: WorkoutShareCardTextStyle
        let heroValue: WorkoutShareCardTextStyle
        let statValue: WorkoutShareCardTextStyle
        let statLabel: WorkoutShareCardTextStyle
    }

    let id: String
    let surface: Surface
    let header: Header?
    let heroPriority: [ShareCardStatKind]
    let supportingPriority: [ShareCardStatKind]
    let maxSupportingStats: Int
    let layout: Layout
    let typography: Typography

    static let defaultSquarePoster = WorkoutShareCardPreset(
        id: "defaultSquarePoster",
        surface: Surface(
            background: .asset("WorkoutSharePosterBackground"),
            cornerRadius: 48,
            borderWidth: 1.2,
            borderOpacity: 0.14
        ),
        header: Header(
            leadingText: "ASCEND",
            trailingText: "STAIR STEPPER",
            topPadding: 12,
            height: 14,
            leadingXRatio: 0.22,
            trailingXRatio: 0.76,
            textY: 7
        ),
        heroPriority: [
            .verticalClimb,
            .steps,
            .duration,
            .calories,
            .avgHeartRate,
        ],
        supportingPriority: [
            .steps,
            .duration,
            .calories,
            .pace,
            .avgHeartRate,
            .addedWeight,
        ],
        maxSupportingStats: 3,
        layout: Layout(
            heroTopPadding: 76,
            heroWidthRatio: 0.76,
            heroLabelTopPadding: 6,
            supportingStatsTopPadding: 260,
            supportingStatsWidthRatio: 0.8,
            supportingStatsSpacing: 12
        ),
        typography: Typography(
            brand: WorkoutShareCardTextStyle(token: .overline, size: 7, tracking: 3.1),
            heroLabel: WorkoutShareCardTextStyle(token: .label, size: 9, tracking: 4.2),
            heroValue: WorkoutShareCardTextStyle(token: .display, size: 80, tracking: -2.4),
            statValue: WorkoutShareCardTextStyle(token: .value, size: 17, tracking: -0.2),
            statLabel: WorkoutShareCardTextStyle(token: .label, size: 7.5, tracking: 2.0)
        )
    )
}
