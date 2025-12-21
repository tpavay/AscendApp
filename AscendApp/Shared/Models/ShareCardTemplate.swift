//
//  ShareCardTemplate.swift
//  AscendApp
//
//  Created by Tyler Pavay on 12/19/25.
//

import Foundation

/// Gender options for filtering share card templates
enum Gender: String, Codable, CaseIterable {
    case male
    case female
}

/// A remotely-hosted share card background template
struct ShareCardTemplate: Identifiable, Codable {
    /// Unique identifier for the template
    let id: String

    /// Firebase Storage path (e.g., "share-card-templates/man-share-card-1.png")
    let storagePath: String

    /// Optional gender filter - nil means universal (shows for everyone)
    let gender: Gender?

    /// Sort order for display in carousel (lower = earlier)
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case storagePath
        case gender
        case sortOrder
    }
}

/// Response structure for Firestore shareCardTemplates document
struct ShareCardTemplatesConfig: Codable {
    let templates: [ShareCardTemplate]
    let version: Int
}
