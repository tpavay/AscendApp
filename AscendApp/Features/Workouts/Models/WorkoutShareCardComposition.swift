//
//  WorkoutShareCardComposition.swift
//  AscendApp
//
//  Created by Codex on 3/28/26.
//

import Foundation

struct WorkoutShareCardComposition: Equatable {
    let preset: WorkoutShareCardPreset
    let heroStat: ShareCardResolvedStat
    let supportingStats: [ShareCardResolvedStat]
    var bestEffortText: String?
}
