//
//  ShareCardStatKind.swift
//  AscendApp
//
//  Created by Codex on 3/28/26.
//

import Foundation

enum ShareCardStatKind: String, CaseIterable, Identifiable {
    case verticalClimb
    case preferredMetric
    case duration
    case calories
    case pace
    case avgHeartRate
    case addedWeight
    case alternateMetric

    var id: String { rawValue }
}

struct ShareCardResolvedStat: Identifiable, Equatable {
    let kind: ShareCardStatKind
    let label: String
    let value: String

    var id: ShareCardStatKind { kind }
}
